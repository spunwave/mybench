// The key values of the sidebar and the setup lines of the Overview tiles stay short: a key value is
// at most 18 characters, a setup line at most 32, in the typical and in the extreme states of every
// instrument (largest magnitudes, both channels on). No sentences, nothing elided.
// That 18 characters fit the sidebar's 160 px row is measured in tst_sidebar.qml.
#include "aeqcontroller.h"
#include "bodecontroller.h"
#include "ctrcontroller.h"
#include "diocontroller.h"
#include "dmmcontroller.h"
#include "dmmlogic.h"
#include "dsacontroller.h"
#include "gencontroller.h"
#include "logcontroller.h"
#include "scopecontroller.h"

#include <mybench/units.h>

#include <QTest>

using namespace Qt::StringLiterals;
using namespace mybench::instruments;

namespace {

constexpr int kKeyMax = 18;
constexpr int kSummaryMax = 32;

// Magnitudes with every SI prefix, three significant digits at their largest.
const QList<double> kMagnitudes{1e-3, 0.0123, 0.1, 0.999, 1, 1.98, 9.99, 10, 12.3, 99.9, 100, 999,
                                1e3, 1.98e3, 9.99e3, 1.23e4, 9.99e4, 1e5, 9.99e5, 1e6, 2e7};

class KeyValues : public QObject
{
    Q_OBJECT

    static void within(const QString& text, int limit)
    {
        QVERIFY2(text.size() <= limit, qPrintable(u"\"%1\" has %2 characters, limit %3"_s.arg(text).arg(text.size()).arg(limit)));
    }

private slots:
    void scope()
    {
        // 0.1 Hz to 1 MHz, 1 mV to 20 V peak to peak (the range is ±10 V).
        for (double f : kMagnitudes)
            for (double pp : kMagnitudes)
                if (f >= 0.1 && f <= 1e6 && pp <= 20)
                    within(ScopeController::keyValueText(f, pp), kKeyMax);
        within(ScopeController::keyValueText(qQNaN(), 19.99), kKeyMax);
        QCOMPARE(ScopeController::keyValueText(1000, 1.98), u"1.00 kHz · 2.0 Vpp"_s);
        QCOMPARE(ScopeController::keyValueText(1000, 0.1), u"1.0 kHz · 100 mVpp"_s);
    }

    void scopeSummary()
    {
        ScopeController c;
        within(c.summary(), kSummaryMax);
        for (double t : {5e-9, 0.5, 0.2, 50.0}) {
            c.setTimePerDiv(t);
            for (double v : {0.01, 0.5, 5.0, 10.0}) {
                c.channel0()->setVoltsPerDiv(v);
                for (auto type : {ScopeController::Edge, ScopeController::Immediate}) {
                    c.setTriggerType(type);
                    within(c.summary(), kSummaryMax);
                }
            }
        }
    }

    void log()
    {
        for (qint64 s : {0, 59, 3599, 86399, 360000, 3599999})
            within(LogController::keyValueText(s), kKeyMax);
        QCOMPARE(LogController::keyValueText(45150), u"REC 12:32:30"_s);
        LogController c;
        within(c.summary(), kSummaryMax);
    }

    void bode()
    {
        within(BodeController::keyValueText(true, 9999, 9999, -1), kKeyMax);
        for (double f : kMagnitudes)
            within(BodeController::keyValueText(false, 0, 0, f), kKeyMax);
        QVERIFY(BodeController::keyValueText(false, 0, 0, -1).isEmpty());
        BodeController c;
        within(c.summary(), kSummaryMax);
        for (double start : {0.1, 1.0, 100.0})
            for (double stop : {1e3, 1e5, 9.99e5}) {
                c.setStartFrequency(start);
                c.setStopFrequency(stop);
                for (int steps : {5, 20, 100}) {
                    c.setStepsPerDecade(steps);
                    within(c.summary(), kSummaryMax);
                }
            }
    }

    void aeq()
    {
        for (double g : {-12.0, -11.5, -9.9, -1.0, -0.4, 0.0, 0.5, 3.0, 9.9, 11.5, 12.0}) {
            within(AeqController::gainsText(false, g, g, g, true), kKeyMax);
            within(AeqController::gainsText(false, g, -g, g, false), kSummaryMax);
        }
        QCOMPARE(AeqController::gainsText(false, 3, 0, -2, true), u"+3 / 0 / −2 dB"_s);
        QCOMPARE(AeqController::gainsText(true, 3, 0, -2, true), u"Bypass"_s);
        AeqController c;
        within(c.summary(), kSummaryMax);
    }

    void dmm()
    {
        for (int f = 0; f <= int(DmmController::Continuity); ++f) {
            const auto function = DmmController::MeterFunction(f);
            for (double range : dmm::defaultRanges(mydaq::DmmFunction(f))) {
                const dmm::DisplayFormat format = dmm::displayFormat(mydaq::DmmFunction(f), range);
                for (double sign : {1.0, -1.0}) {
                    const double value = sign * dmm::overloadLimit(mydaq::DmmFunction(f), range);
                    const QString text = dmm::formatNumber(value, format);
                    within(DmmController::keyValueText(function, text, format.unit), kKeyMax);
                }
            }
            within(DmmController::keyValueText(function, dmm::overloadText(mydaq::DmmFunction(f), -1.0, true), QString()), kKeyMax);
        }
        QCOMPARE(DmmController::keyValueText(DmmController::DcVoltage, u"1.2346"_s, u"V"_s), u"1.2346 V DC"_s);
        DmmController c;
        for (int f = 0; f <= int(DmmController::Continuity); ++f) {
            c.setSelectedFunction(DmmController::MeterFunction(f));
            for (bool autoRange : {true, false}) {
                c.setAutoRange(autoRange);
                within(c.summary(), kSummaryMax);
            }
        }
    }

    void gen()
    {
        const QString longName = u"A very long waveform file name.csv"_s;
        for (double f : kMagnitudes)
            for (double amplitude : {0.001, 0.123, 1.0, 9.99, 10.0, 20.0}) {
                within(GenController::describeChannel(GenChannel::Function, f, amplitude, 0, {}), kKeyMax);
                within(GenController::describeChannel(GenChannel::Function, f, amplitude, 0, {}, true), 9 + 0 + 0 + 8);
            }
        for (double dc : {-10.0, -9.99, -0.001, 0.0, 5.0, 10.0})
            within(GenController::describeChannel(GenChannel::Dc, 0, 0, dc, {}), kKeyMax);
        within(GenController::describeChannel(GenChannel::Arbitrary, 0, 0, 0, longName), kKeyMax);
        // Both channels on, one on, none on.
        const QString both = GenController::keyValueText(true, u"AO 0"_s, u"AO 1"_s, u"x"_s, u"y"_s);
        within(both, kKeyMax);
        within(GenController::keyValueText(true, u"AO 0"_s, u"AO 1"_s, {},
                                           GenController::describeChannel(GenChannel::Function, 1e5, 10.0, 0, {})), kKeyMax);
        within(GenController::keyValueText(true, u"AO 0"_s, u"AO 1"_s, {}, {}), kKeyMax);
        QVERIFY(GenController::keyValueText(false, u"AO 0"_s, u"AO 1"_s, u"x"_s, {}).isEmpty());
        QCOMPARE(GenController::describeChannel(GenChannel::Function, 310, 1.2, 0, {}), u"310 Hz · 1.2 Vpp"_s);

        GenController c;
        within(c.summary(), kSummaryMax);
        for (GenChannel* ch : {c.channel0(), c.channel1()}) {
            ch->setMode(GenChannel::Function);
            ch->setFrequency(123456);
            ch->setAmplitude(10);
        }
        within(c.summary(), kSummaryMax);
        c.channel1()->setMode(GenChannel::Dc);
        c.channel1()->setDcLevel(-9.99);
        within(c.summary(), kSummaryMax);
        c.channel0()->setMode(GenChannel::Off);
        within(c.summary(), kSummaryMax);
    }

    void dio()
    {
        QCOMPARE(DioController::keyValueText(0x0F, 0x00), u"In 0x0F · Out 0x00"_s);
        for (int in : {-1, 0, 0xFF})
            for (int out : {-1, 0, 0xFF})
                within(DioController::keyValueText(in, out), kKeyMax);
        DioController c;
        within(c.summary(), kSummaryMax);
    }

    void ctr()
    {
        within(CtrController::keyValueText(true, u"4294967295"_s), kKeyMax);
        within(CtrController::keyValueText(false, u"-12345.6789 inches"_s), kKeyMax);
        for (const QString unit : {u"Hz"_s, u"s"_s})
            for (double f : kMagnitudes)
                for (double sign : {1.0, -1.0})
                    within(CtrController::keyValueText(false, mybench::Units::format(f * sign, unit, 6, false)), kKeyMax);
        CtrController c;
        for (int m = int(CtrController::CountEdges); m <= int(CtrController::AngularEncoder); ++m) {
            c.setMeasurement(CtrController::Measurement(m));
            within(c.summary(), kSummaryMax);
        }
    }

    void dsa()
    {
        for (double f : kMagnitudes)
            for (const QString level : {u"−6.02 dBV"_s, u"−120.00 dBV"_s, u"0.123 V²"_s, u"1.23e-05 V² rms"_s})
                within(DsaController::keyValueText(mybench::Units::format(f, u"Hz"_s, 3, false), level), kKeyMax);
        QCOMPARE(DsaController::keyValueText(u"1.00 kHz"_s, u"−6.02 dBV"_s), u"1.00 kHz −6.02 dBV"_s);
        DsaController c;
        within(c.summary(), kSummaryMax);
    }
};

}  // namespace

QTEST_GUILESS_MAIN(KeyValues)
#include "tst_keyvalues.moc"
