#include "bodesweep.h"

#include "bodemath.h"

#include <mydaq/dsp/measure.h>
#include <mydaq/dsp/waveform.h>

#include <QCoreApplication>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <thread>

namespace mybench::instruments::bode {

namespace {

bool sameConfig(const mydaq::AiConfig& a, const mydaq::AiConfig& b)
{
    if (a.channels.size() != b.channels.size() || a.sampleRate != b.sampleRate || a.mode != b.mode
        || a.samplesPerChannel != b.samplesPerChannel)
        return false;
    for (size_t i = 0; i < a.channels.size(); ++i)
        if (a.channels[i].channel != b.channels[i].channel || a.channels[i].range != b.channels[i].range)
            return false;
    return true;
}

}  // namespace

BodeSweeper::BodeSweeper(mydaq::Device& device, std::function<bool()> stopRequested)
    : m_device(device), m_stop(std::move(stopRequested))
{
}

BodeSweeper::~BodeSweeper()
{
    if (!m_finished)
        finish();
}

QString BodeSweeper::noStimulusMessage(mydaq::AoChannel output, bool audioInputs)
{
    if (audioInputs || mydaq::isAudio(output))
        return QCoreApplication::translate("BodeSweeper", "No stimulus signal on %1. Connect %2 to %1, then run again.")
            .arg(audioInputs ? QStringLiteral("Audio In L") : QStringLiteral("AI 0+"),
                 mydaq::isAudio(output) ? QStringLiteral("Audio Out") : output == mydaq::AoChannel::AO1 ? QStringLiteral("AO 1") : QStringLiteral("AO 0"));
    return QCoreApplication::translate("BodeSweeper",
                                       "No stimulus signal on AI 0. Connect %1 to AI 0+ (and AI 0- to AGND), "
                                       "then run again.")
        .arg(output == mydaq::AoChannel::AO1 ? QStringLiteral("AO 1") : QStringLiteral("AO 0"));
}

void BodeSweeper::finish()
{
    m_finished = true;
    m_ai.reset();
    const bool generated = m_ao != nullptr;
    m_ao.reset();
    if (generated) {
        try {
            if (!mydaq::isAudio(m_output))
                m_device.aoWriteStatic(m_output, 0.0);   // safe state
        } catch (const mydaq::DeviceError&) {
            // Device gone: nothing to reset.
        }
    }
}

bool BodeSweeper::generate(double frequency, double amplitude, double* actualFrequency)
{
    const double maxRate = m_device.maxAoRate();
    const mydaq::dsp::BufferPlan plan = mydaq::dsp::planPeriodicBuffer(
        frequency, stimulusRateLimit(frequency, maxRate),
        [this](double rate) { return m_device.coerceAoRate(rate); }, 100000, 2, 1e-6);
    mydaq::dsp::WaveformParams sine;
    sine.type = mydaq::dsp::Waveform::Sine;
    sine.frequency = plan.frequency;
    sine.amplitude = amplitude;
    const std::vector<double> buffer = mydaq::dsp::generatePeriodic(sine, plan);

    // A new AO task per point (as ELVISmx does), written and started with its buffer.
    m_ao.reset();
    mydaq::AoConfig config;
    if (mydaq::isAudio(m_output))   // Audio Out: the same sine on left and right (±2 V)
        config.channels = {{mydaq::AoChannel::AudioOutLeft, 2.0}, {mydaq::AoChannel::AudioOutRight, 2.0}};
    else
        config.channels = {{m_output, 10.0}};
    config.sampleRate = plan.sampleRate;
    config.mode = mydaq::SampleMode::Continuous;
    config.regenerate = true;
    m_ao = m_device.createAoTask(config);
    m_ao->write(config.channels.size() == 2 ? std::vector<std::vector<double>>{buffer, buffer}
                                            : std::vector<std::vector<double>>{buffer});
    m_ao->start();
    *actualFrequency = plan.frequency;
    return true;
}

std::optional<BodeSweeper::Record> BodeSweeper::acquire(double rate, int samples, double stimulusRange,
                                                        double responseRange)
{
    mydaq::AiConfig config;
    if (m_audioInputs) {
        stimulusRange = responseRange = 2.0;   // the audio inputs have one fixed range
        config.channels = {{mydaq::AiChannel::AudioInLeft, 2.0}, {mydaq::AiChannel::AudioInRight, 2.0}};
    } else {
        config.channels = {{mydaq::AiChannel::AI0, stimulusRange}, {mydaq::AiChannel::AI1, responseRange}};
    }
    config.sampleRate = m_device.coerceAiRate(rate);
    config.mode = mydaq::SampleMode::Finite;
    config.samplesPerChannel = samples;
    if (!m_ai || !sameConfig(config, m_aiConfig)) {
        m_ai.reset();
        m_ai = m_device.createAiTask(config);
        m_aiConfig = config;
    }
    Record record;
    record.rate = m_ai->sampleRate();
    record.skew = m_ai->channelSkew();
    record.stimulus.reserve(size_t(samples));
    record.response.reserve(size_t(samples));
    m_ai->start();
    // Chunks of about 100 ms so Stop acts quickly.
    const int64_t chunk = std::max<int64_t>(1, int64_t(record.rate * 0.1));
    int64_t remaining = samples;
    while (remaining > 0) {
        if (m_stop()) {
            m_ai->stop();
            return std::nullopt;
        }
        const int64_t n = std::min(chunk, remaining);
        const int timeout = int(1000.0 * double(n) / record.rate) + 500;
        const auto data = m_ai->read(n, timeout);
        record.stimulus.insert(record.stimulus.end(), data[0].begin(), data[0].end());
        record.response.insert(record.response.end(), data[1].begin(), data[1].end());
        remaining -= n;
    }
    m_ai->stop();
    return record;
}

std::optional<MeasuredPoint> BodeSweeper::measure(double frequency, const SweepOptions& options)
{
    if (options.output != m_output || options.audioInputs != m_audioInputs) {
        m_ai.reset();
        m_ao.reset();
        m_output = options.output;
        m_audioInputs = options.audioInputs;
    }
    MeasuredPoint point;
    generate(frequency, options.amplitude, &point.frequency);
    const double f = point.frequency;

    double stimulusRange = 10;
    double responseRange = 10;
    if (options.rangeProbe) {
        // ELVISmx: 16 000 samples on ±10 V at the highest rate pick the ranges.
        const auto probe = acquire(rangeProbeRate(m_device.maxAiRate()), kRangeProbeSamples, 10, 10);
        if (!probe)
            return std::nullopt;
        stimulusRange = selectRange(peakMagnitude(probe->stimulus));
        responseRange = selectRange(peakMagnitude(probe->response));
        if (m_audioInputs)
            stimulusRange = responseRange = 2;
    } else {
        stimulusRange = options.amplitude <= 1.8 ? 2 : 10;
        responseRange = m_firstPoint ? 10 : m_responseRange;
        if (m_audioInputs)
            stimulusRange = responseRange = 2;
        double wait = settlingSeconds(f) + (m_firstPoint ? 0.05 : 0.0);
        while (wait > 0) {
            if (m_stop())
                return std::nullopt;
            const double step = std::min(wait, 0.05);
            std::this_thread::sleep_for(std::chrono::duration<double>(step));
            wait -= step;
        }
    }
    m_firstPoint = false;

    const double rate = acquisitionRate(f, m_device.maxAiRate());
    const int averages = std::clamp(options.averages, 1, kMaxAveragesPerPoint);
    std::complex<double> sum;
    double stimulusAmplitude = 0;
    double responseAmplitude = 0;
    double responsePeak = 0;
    for (int a = 0; a < averages; ++a) {
        std::optional<Record> record;
        for (;;) {
            record = acquire(rate, kAiSamples, stimulusRange, responseRange);
            if (!record)
                return std::nullopt;
            bool again = false;
            if (!m_audioInputs && stimulusRange < 10 && isClipped(record->stimulus, stimulusRange)) {
                stimulusRange = 10;
                again = true;
            }
            if (!m_audioInputs && responseRange < 10 && isClipped(record->response, responseRange)) {
                responseRange = 10;
                again = true;
            }
            if (!again)
                break;
        }
        const mydaq::dsp::Tone stimulus = mydaq::dsp::fitSine(record->stimulus, record->rate, f);
        const mydaq::dsp::Tone response = mydaq::dsp::fitSine(record->response, record->rate, f);
        if (!(stimulus.amplitude >= std::max(0.05 * options.amplitude, 0.005)))
            throw mydaq::DeviceError(mydaq::DeviceError::Generic, noStimulusMessage(m_output, m_audioInputs));
        if ((m_audioInputs || responseRange >= 10) && isClipped(record->response, m_audioInputs ? 2 : 10))
            point.clipped = true;
        sum += bode::response(stimulus.amplitude, stimulus.phase, response.amplitude, response.phase, f,
                              record->skew);
        stimulusAmplitude += stimulus.amplitude;
        responseAmplitude += response.amplitude;
        responsePeak = std::max(responsePeak, std::abs(response.offset) + response.amplitude);
        point.sampleRate = record->rate;
    }
    point.response = sum / double(averages);
    point.stimulusAmplitude = stimulusAmplitude / averages;
    point.responseAmplitude = responseAmplitude / averages;
    point.stimulusRange = stimulusRange;
    point.responseRange = responseRange;
    m_responseRange = responsePeak < 1.8 ? 2 : 10;
    return point;
}

}  // namespace mybench::instruments::bode
