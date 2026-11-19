// BodeSweeper: measures one frequency point after another on a mydaq::Device (worker thread).
//
// Per point: a regenerated sine buffer of whole periods on the stimulus output (about 10 000
// samples per period); input ranges (Standard: a 16 000-sample pre-measurement on ±10 V, which also
// settles the circuit; Fast: no pre-measurement, the response range adapts from the previous point
// and the circuit settles for 3 periods); 16 000 samples per channel at 3200·f; a channel clipped
// on ±2 V is measured again on ±10 V; sine fit on both channels, H = response / stimulus with the
// phase corrected for the AI channel skew. `averages` > 1 averages several records.
// finish() stops the generation and leaves AO 0 at 0 V.
#pragma once

#include <mydaq/device.h>

#include <complex>
#include <functional>
#include <memory>
#include <optional>
#include <vector>

namespace mybench::instruments::bode {

struct SweepOptions {
    double amplitude = 2.0;        // V peak of the stimulus
    bool rangeProbe = true;        // Standard (ELVISmx) mode; false = Fast
    int averages = 1;              // records averaged per point (1..16)
    // Stimulus output: AO 0 / AO 1 (±10 V) or AudioOutput Left + Right (the same sine on both, ±2 V).
    mydaq::AoChannel output = mydaq::AoChannel::AO0;
    // Input pair: AI 0 + AI 1, or AudioInput Left + Right (AC coupled, fixed ±2 V). The stimulus is
    // measured on the first channel, the response on the second.
    bool audioInputs = false;
};

struct MeasuredPoint {
    double frequency = 0;              // generated frequency (Hz)
    std::complex<double> response;     // H, non-inverted, skew-corrected
    bool clipped = false;              // response clipped on ±10 V
    double stimulusAmplitude = 0;      // V peak (first input)
    double responseAmplitude = 0;      // V peak (second input)
    double stimulusRange = 10;         // ±V used
    double responseRange = 10;
    double sampleRate = 0;             // AI rate of the measurement
};

class BodeSweeper
{
public:
    // `stopRequested` is polled between reads (every ≤ 100 ms).
    BodeSweeper(mydaq::Device& device, std::function<bool()> stopRequested);
    ~BodeSweeper();

    // Measures `frequency` (requested Hz). Returns nullopt when stopped. Throws
    // mydaq::DeviceError on device errors and when AI 0 sees no stimulus.
    std::optional<MeasuredPoint> measure(double frequency, const SweepOptions& options);
    // Destroys the tasks and writes 0 V to AO 0 (safe state). Called by the destructor too.
    void finish();

    // Message of the "no stimulus" error.
    static QString noStimulusMessage(mydaq::AoChannel output = mydaq::AoChannel::AO0, bool audioInputs = false);

private:
    struct Record {
        std::vector<double> stimulus;
        std::vector<double> response;
        double rate = 0;
        double skew = 0;
    };
    bool generate(double frequency, double amplitude, double* actualFrequency);
    std::optional<Record> acquire(double rate, int samples, double stimulusRange, double responseRange);

    mydaq::Device& m_device;
    mydaq::AoChannel m_output = mydaq::AoChannel::AO0;
    bool m_audioInputs = false;
    std::function<bool()> m_stop;
    std::unique_ptr<mydaq::AoTask> m_ao;
    std::unique_ptr<mydaq::AiTask> m_ai;
    mydaq::AiConfig m_aiConfig;
    double m_responseRange = 10;   // Fast mode: range for the next point
    bool m_firstPoint = true;
    bool m_finished = false;
};

}  // namespace mybench::instruments::bode
