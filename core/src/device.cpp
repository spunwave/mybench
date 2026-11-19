#include "mydaq/device.h"

#include <cmath>
#include <functional>

namespace mydaq {

QString toString(AiChannel ch)
{
    switch (ch) {
    case AiChannel::AI0: return QStringLiteral("AI 0");
    case AiChannel::AI1: return QStringLiteral("AI 1");
    case AiChannel::AudioInLeft: return QStringLiteral("AudioInput Left");
    case AiChannel::AudioInRight: return QStringLiteral("AudioInput Right");
    }
    return {};
}

QString toString(AoChannel ch)
{
    switch (ch) {
    case AoChannel::AO0: return QStringLiteral("AO 0");
    case AoChannel::AO1: return QStringLiteral("AO 1");
    case AoChannel::AudioOutLeft: return QStringLiteral("AudioOutput Left");
    case AoChannel::AudioOutRight: return QStringLiteral("AudioOutput Right");
    }
    return {};
}

QString toString(DmmFunction f)
{
    switch (f) {
    case DmmFunction::DcVoltage: return QStringLiteral("DC Voltage");
    case DmmFunction::AcVoltage: return QStringLiteral("AC Voltage");
    case DmmFunction::DcCurrent: return QStringLiteral("DC Current");
    case DmmFunction::AcCurrent: return QStringLiteral("AC Current");
    case DmmFunction::Resistance: return QStringLiteral("Resistance");
    case DmmFunction::Diode: return QStringLiteral("Diode");
    case DmmFunction::Continuity: return QStringLiteral("Continuity");
    }
    return {};
}

QString toString(CounterMeasurement m)
{
    switch (m) {
    case CounterMeasurement::CountEdges: return QStringLiteral("Count Edges");
    case CounterMeasurement::Frequency: return QStringLiteral("Frequency");
    case CounterMeasurement::Period: return QStringLiteral("Period");
    case CounterMeasurement::PulseWidth: return QStringLiteral("Pulse Width");
    case CounterMeasurement::SemiPeriod: return QStringLiteral("Semi-Period");
    case CounterMeasurement::TwoEdgeSeparation: return QStringLiteral("Two-Edge Separation");
    case CounterMeasurement::LinearEncoder: return QStringLiteral("Linear Encoder");
    case CounterMeasurement::AngularEncoder: return QStringLiteral("Angular Encoder");
    }
    return {};
}

QString unitOf(DmmFunction f)
{
    switch (f) {
    case DmmFunction::DcVoltage:
    case DmmFunction::AcVoltage:
    case DmmFunction::Diode: return QStringLiteral("V");
    case DmmFunction::DcCurrent:
    case DmmFunction::AcCurrent: return QStringLiteral("A");
    case DmmFunction::Resistance:
    case DmmFunction::Continuity: return QStringLiteral("Ω");
    }
    return {};
}

namespace {
void attempt(SelfTestResult& r, const QString& name, const std::function<QString()>& check)
{
    try {
        r.checks.push_back({name, true, check()});
    } catch (const std::exception& e) {
        r.checks.push_back({name, false, QString::fromUtf8(e.what())});
    }
}
}  // namespace

SelfTestResult Device::selfTest()
{
    SelfTestResult r;
    for (AiChannel ch : {AiChannel::AI0, AiChannel::AI1}) {
        attempt(r, toString(ch), [&] {
            const double v = aiReadStatic(ch, 10.0);
            if (!std::isfinite(v) || std::abs(v) > 10.5)
                throw DeviceError(DeviceError::Generic, QStringLiteral("reading %1 V is outside the ±10 V range").arg(v));
            return QStringLiteral("%1 V (±10 V range)").arg(v, 0, 'f', 4);
        });
    }
    attempt(r, QStringLiteral("Multimeter"), [&] {
        const DmmReading d = dmmRead(DmmFunction::DcVoltage, 20.0);
        return d.overload ? QStringLiteral("answers (overload on DC V 20 V)") : QStringLiteral("DC V: %1 V").arg(d.value, 0, 'f', 4);
    });
    attempt(r, QStringLiteral("Digital I/O"), [&] {
        return QStringLiteral("DIO 0-7 levels 0x%1").arg(dioRead(), 2, 16, QLatin1Char('0'));
    });
    return r;
}

}  // namespace mydaq
