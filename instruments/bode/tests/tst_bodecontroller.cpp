// BodeController against the simulated myDAQ: a fast sweep, markers, polarity, references,
// validation, pause/resume and export.
#include "bodecontroller.h"

#include <mybench/framework.h>

#include <QRegularExpression>
#include <QSettings>
#include <QTemporaryDir>
#include <QTest>

#include <cmath>

using namespace mybench;
using namespace mybench::instruments;
using namespace Qt::StringLiterals;

class TestBodeController : public QObject
{
    Q_OBJECT

    BodeController* bode() const
    {
        return qobject_cast<BodeController*>(InstrumentRegistry::instance()->controller(u"bode"_s));
    }

private slots:
    void initTestCase()
    {
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, m_dir.path());
        QCoreApplication::setOrganizationName(u"MYBENCH-test"_s);
        QCoreApplication::setApplicationName(u"tst_bodecontroller"_s);
        InstrumentController::setRestoreSavedSettings(false);
        QVERIFY(DeviceHub::instance()->isSimulated());
        registerBode(*InstrumentRegistry::instance());
        InstrumentRegistry::instance()->createAll();
        QVERIFY(bode());
    }

    void cleanupTestCase() { InstrumentRegistry::instance()->shutdown(); }

    void defaults()
    {
        BodeController* c = bode();
        QCOMPARE(c->startFrequency(), 100.0);
        QCOMPARE(c->stopFrequency(), 10000.0);
        QCOMPARE(c->stepsPerDecade(), 5);
        QCOMPARE(c->peakAmplitude(), 2.0);
        QCOMPARE(c->polarity(), BodeController::Normal);
        QCOMPARE(c->mapping(), BodeController::Logarithmic);
        QVERIFY(c->autoscale());
        QVERIFY(!c->cursorsOn());
        QCOMPARE(c->sweepMode(), BodeController::Standard);
        QCOMPARE(c->stimulus(), BodeController::StimulusAO0);
        QCOMPARE(c->inputPair(), BodeController::InputsAnalog);
        QVERIFY(!c->audioPath());
        QCOMPARE(c->stimulusName(), u"AO 0"_s);
        QCOMPARE(c->stimulusInputName(), u"AI 0"_s);
        QCOMPARE(c->responseInputName(), u"AI 1"_s);
        QCOMPARE(c->plannedPoints(), 11);
        QVERIFY(!c->supportsSingle());
        QCOMPARE(c->readoutGainDb(), -std::numeric_limits<double>::infinity());
        // Limits (ELVISmx): 1 Hz ... 20 kHz, 0 ... 5 V.
        c->setStopFrequency(1e6);
        QCOMPARE(c->stopFrequency(), 20000.0);
        c->setPeakAmplitude(7);
        QCOMPARE(c->peakAmplitude(), 5.0);
        c->resetSettings();
        QCOMPARE(c->stopFrequency(), 10000.0);
        QCOMPARE(c->peakAmplitude(), 2.0);
    }

    void startAboveStopIsRefused()
    {
        BodeController* c = bode();
        c->setStartFrequency(5000);
        c->setStopFrequency(1000);
        QVERIFY(!c->settingsValid());
        c->run();
        QVERIFY(!c->isRunning());
        QCOMPARE(c->inputWarning(), u"Start above stop frequency"_s);   // a warning, not a device error
        QVERIFY(!c->hasError());
        c->resetSettings();
        c->clearError();
    }

    // A 0 V stimulus can never be measured, so the run is refused up front.
    void zeroAmplitudeIsRefused()
    {
        BodeController* c = bode();
        c->setPeakAmplitude(0);
        c->run();
        QVERIFY(!c->isRunning());
        QVERIFY(c->inputWarning().contains(u"Peak Amplitude"_s));
        QVERIFY(!c->hasError());
        c->resetSettings();
        c->clearError();
    }

    // Autoscale off jumps to fixed ranges.
    void fixedRanges()
    {
        QCOMPARE(BodeController::fixedGainMin(), -30.0);
        QCOMPARE(BodeController::fixedGainMax(), 5.0);
        QCOMPARE(BodeController::fixedPhaseMin(), -360.0);
        QCOMPARE(BodeController::fixedPhaseMax(), 360.0);
        QCOMPARE(BodeController::fixedPhaseStep(), 90.0);
    }

    void channelsPersistAndReset()
    {
        BodeController* c = bode();
        c->setStimulus(BodeController::StimulusAO1);
        c->setInputPair(BodeController::InputsAudio);
        QCOMPARE(c->stimulusName(), u"AO 1"_s);
        QCOMPARE(c->stimulusInputName(), u"Audio L"_s);
        QCOMPARE(c->responseInputName(), u"Audio R"_s);
        const QJsonObject saved = c->saveSettings();
        c->resetSettings();
        QCOMPARE(c->stimulus(), BodeController::StimulusAO0);
        QCOMPARE(c->inputPair(), BodeController::InputsAnalog);
        c->restoreSettings(saved);
        QCOMPARE(c->stimulus(), BodeController::StimulusAO1);
        QCOMPARE(c->inputPair(), BodeController::InputsAudio);
        // An old session without the keys keeps the defaults; out-of-range values are clamped.
        QJsonObject old = saved;
        old.remove(u"stimulus"_s);
        old.remove(u"inputPair"_s);
        c->resetSettings();
        c->restoreSettings(old);
        QCOMPARE(c->stimulus(), BodeController::StimulusAO0);
        QCOMPARE(c->inputPair(), BodeController::InputsAnalog);
        c->setStimulus(BodeController::Stimulus(9));
        QCOMPARE(c->stimulus(), BodeController::StimulusAudio);
        c->resetSettings();
    }

    // The audio path is AC coupled and ±2 V: the sweep starts at 20 Hz, the amplitude stays under 1.8 V.
    void audioLimits()
    {
        BodeController* c = bode();
        c->setStartFrequency(1);
        c->setStopFrequency(10000);
        c->setPeakAmplitude(5);
        QCOMPARE(c->effectiveStart(), 1.0);
        QCOMPARE(c->effectiveAmplitude(), 5.0);
        c->setInputPair(BodeController::InputsAudio);
        QVERIFY(c->audioPath());
        QCOMPARE(c->effectiveStart(), 20.0);
        QCOMPARE(c->effectiveAmplitude(), 1.8);
        QCOMPARE(c->startFrequency(), 1.0);   // the setting itself is kept
        c->setInputPair(BodeController::InputsAnalog);
        c->setStimulus(BodeController::StimulusAudio);
        QVERIFY(c->audioPath());
        // Stop below 20 Hz cannot be measured on the audio path.
        c->setStartFrequency(1);
        c->setStopFrequency(10);
        QVERIFY(!c->settingsValid());
        c->run();
        QVERIFY(!c->isRunning());
        QVERIFY(c->inputWarning().contains(u"20 Hz"_s));
        QVERIFY(!c->hasError());
        c->resetSettings();
        c->clearError();
    }

    // Audio Out L -> Audio In L / R through the simulator's AC-coupled loopback (no filter in it:
    // gain 0 dB). Starting below 20 Hz is raised to 20 Hz.
    void audioSweepRuns()
    {
        BodeController* c = bode();
        c->setStimulus(BodeController::StimulusAudio);
        c->setInputPair(BodeController::InputsAudio);
        c->setSweepMode(BodeController::Fast);
        c->setStartFrequency(10);
        c->setStopFrequency(10000);
        c->setStepsPerDecade(2);
        c->run();
        QTRY_VERIFY_WITH_TIMEOUT(c->state() == InstrumentController::Idle, 30000);
        QVERIFY2(!c->hasError(), qPrintable(c->errorText()));
        QVERIFY(c->pointCount() > 3);
        QVERIFY2(std::abs(c->dataMinFrequency() - 20) < 0.1, qPrintable(QString::number(c->dataMinFrequency())));
        c->setCursorsOn(true);
        c->setCursorFrequency(1000);
        QVERIFY2(std::abs(c->readoutGainDb()) < 0.2, qPrintable(QString::number(c->readoutGainDb())));
        QVERIFY(c->exportMetadata().value(u"Stimulus"_s).toString().contains(u"Audio L"_s));
        c->resetSettings();
        c->clearSweep();
    }

    // AO 1 is not wired in the simulator: the run ends with the "no stimulus" message naming AO 1
    // instead of hanging.
    void ao1WithoutWireReportsNoStimulus()
    {
        BodeController* c = bode();
        c->setStimulus(BodeController::StimulusAO1);
        c->setSweepMode(BodeController::Fast);
        c->setStepsPerDecade(1);
        c->run();
        QTRY_VERIFY_WITH_TIMEOUT(c->state() == InstrumentController::Idle || c->hasError(), 20000);
        QVERIFY(c->hasError());
        QVERIFY2(c->errorText().contains(u"AO 1"_s), qPrintable(c->errorText()));
        c->resetSettings();
        c->clearError();
        c->clearSweep();
    }

    void fastSweep()
    {
        BodeController* c = bode();
        c->setSweepMode(BodeController::Fast);
        c->setStartFrequency(100);
        c->setStopFrequency(10000);
        c->setStepsPerDecade(5);
        c->run();
        QTRY_VERIFY_WITH_TIMEOUT(c->state() == InstrumentController::Idle, 20000);
        QVERIFY2(!c->hasError(), qPrintable(c->errorText()));
        QCOMPARE(c->pointCount(), 11);
        QCOMPARE(c->totalPoints(), 11);
        QVERIFY(c->hasData());
        QCOMPARE(c->gain()->count(), 11);
        // Simulator RC low-pass at 1 kHz: -3 dB / -45 deg there, one -3 dB marker at ~1 kHz.
        c->setCursorsOn(true);
        c->setCursorFrequency(1000);
        QVERIFY(std::abs(c->readoutFrequency() - 1000) < 0.01);
        QVERIFY2(std::abs(c->readoutGainDb() + 3.01) < 0.05, qPrintable(QString::number(c->readoutGainDb())));
        QVERIFY2(std::abs(c->readoutPhase() + 45.0) < 0.5, qPrintable(QString::number(c->readoutPhase())));
        QCOMPARE(c->cutoffFrequencies().size(), 1);
        QVERIFY2(std::abs(c->cutoffFrequencies().first() / 1000 - 1) < 0.03,
                 qPrintable(QString::number(c->cutoffFrequencies().first())));
        QVERIFY(std::isnan(c->unityGainFrequency()));

        // Polarity is a display transform: 1 kHz reads +135 deg, gain unchanged.
        c->setPolarity(BodeController::Inverted);
        QVERIFY(std::abs(c->readoutPhase() - 135.0) < 0.5);
        QVERIFY(std::abs(c->readoutGainDb() + 3.01) < 0.05);
        c->setPolarity(BodeController::Normal);

        // Mapping Linear: the gain trace holds ratios.
        c->setMapping(BodeController::Linear);
        QVERIFY(std::abs(c->gain()->valueAt(1000) - 0.7071) < 0.01);
        c->setMapping(BodeController::Logarithmic);
        QVERIFY(std::abs(c->gain()->valueAt(1000) + 3.01) < 0.05);

        // Cursor stepping.
        const int index = c->cursorIndex();
        c->cursorRight();
        QCOMPARE(c->cursorIndex(), index + 1);
        c->cursorLeft();
        c->cursorLeft();
        QCOMPARE(c->cursorIndex(), index - 1);

        // Export.
        const QVariantMap metadata = c->exportMetadata();
        QVERIFY(metadata.value(u"Stimulus"_s).toString().contains(u"AI 1"_s));
        QTemporaryDir dir;
        QVERIFY(c->exportData(QUrl::fromLocalFile(dir.filePath(u"bode.csv"_s))));
        QFile file(dir.filePath(u"bode.csv"_s));
        QVERIFY(file.open(QIODevice::ReadOnly));
        const QString text = QString::fromUtf8(file.readAll());
        QVERIFY(text.contains(u"Frequency (Hz),Gain,Gain (dB),Phase (deg),Clipped"_s));
        QVERIFY(text.contains(u"# Peak amplitude: 2.00 V, Op-amp signal polarity: Normal"_s));

        // Keep as reference, then persistence of references.
        QVERIFY(c->keepAsReference(u"RC"_s));
        QCOMPARE(c->references().size(), 1);
        QCOMPARE(c->referenceGain(0)->count(), 11);
        const QJsonObject saved = c->saveSettings();
        c->clearReferences();
        QCOMPARE(c->references().size(), 0);
        c->restoreSettings(saved);
        QCOMPARE(c->references().size(), 1);
        QCOMPARE(c->references().first().toMap().value(u"name"_s).toString(), u"RC"_s);
        QCOMPARE(c->referenceGain(0)->count(), 11);
        c->clearReferences();
    }

    // Cursors On starts on the first point and keeps its index in a new sweep; ELVISmx text log and
    // Print metadata.
    void cursorStartsOnFirstPoint()
    {
        BodeController* c = bode();
        QVERIFY(c->pointCount() == 11);
        c->setCursorsOn(false);
        c->setCursorsOn(true);
        QCOMPARE(c->cursorIndex(), 0);
        QVERIFY(std::abs(c->readoutFrequency() - 100) < 0.01);
        c->cursorRight();
        c->cursorRight();
        QCOMPARE(c->cursorIndex(), 2);
        c->run();   // new sweep: the cursor keeps its index while points come in
        QVERIFY(c->cursorIndex() == 2);
        QTRY_VERIFY_WITH_TIMEOUT(c->state() == InstrumentController::Idle, 20000);
        QCOMPARE(c->cursorIndex(), 2);
        QCOMPARE(c->pointCount(), 11);
        c->setCursorsOn(false);
        c->setCursorsOn(true);
        QCOMPARE(c->cursorIndex(), 0);
    }

    // A second cursor (C2, last point when cursors go on) and the difference C2 − C1:
    // the simulator's RC low-pass falls at −20 dB/decade well above 1 kHz.
    void secondCursorAndSlope()
    {
        BodeController* c = bode();
        QVERIFY(c->pointCount() == 11);
        c->setCursorsOn(false);
        c->setCursorsOn(true);
        QCOMPARE(c->cursorIndex(), 0);
        QCOMPARE(c->cursor2Index(), 10);
        QVERIFY(std::abs(c->cursor2Frequency() - 10000) < 0.01);
        c->setCursorFrequency(4000);
        c->setCursor2Frequency(10000);
        QVERIFY(std::abs(c->cursorFrequency() / 3981 - 1) < 0.01);   // 5 points / decade
        QVERIFY(std::isfinite(c->cursorGainDb()));
        QVERIFY(c->cursor2GainDb() < c->cursorGainDb());
        const double slope = c->cursorSlope();
        QVERIFY2(slope < -15 && slope > -21, qPrintable(QString::number(slope)));
        QVERIFY(c->cursor2Phase() < c->cursorPhase());
        // Same point: no slope.
        c->setCursor2Index(c->cursorIndex());
        QVERIFY(std::isnan(c->cursorSlope()));
        c->setCursorIndex(0);   // as the next test expects (cursors on, C1 on the first point)
    }

    void printMetadataAndTxtLog()
    {
        BodeController* c = bode();
        const QVariantMap metadata = c->exportMetadata();
        QCOMPARE(metadata.value(u"Graph mapping"_s).toString(), u"Logarithmic"_s);
        QVERIFY(metadata.value(u"Cursors"_s).toString().startsWith(u"On"_s));
        QCOMPARE(metadata.value(u"Peak amplitude"_s).toString(), u"2.00 V, Op-amp signal polarity: Normal"_s);
        QTemporaryDir dir;
        const QString path = dir.filePath(u"bode.txt"_s);
        QVERIFY(c->exportData(QUrl::fromLocalFile(path)));
        QFile file(path);
        QVERIFY(file.open(QIODevice::ReadOnly));
        // The ELVISmx-style TXT log is CR LF on every platform (exports are written in binary mode).
        const QStringList lines = QString::fromUtf8(file.readAll()).split(QRegularExpression(u"\r?\n"_s), Qt::SkipEmptyParts);
        QCOMPARE(lines.size(), 2 + 1 + 11);
        QVERIFY(lines[0].contains(u'\t'));
        QCOMPARE(lines[1], u"Amplitude: 2.00 V"_s);
        QCOMPARE(lines[2], u"Freq (Hz)\tGain (dB)\tPhase (deg)"_s);
        const QStringList first = lines[3].split(u'\t');
        QCOMPARE(first.size(), 3);
        QCOMPARE(first[0], u"100.000"_s);
        file.close();   // Windows refuses to replace a file that is still open
        c->setMapping(BodeController::Linear);
        QVERIFY(c->exportData(QUrl::fromLocalFile(path)));
        QVERIFY(file.open(QIODevice::ReadOnly));
        QVERIFY(QString::fromUtf8(file.readAll()).contains(u"Gain (Linear)"_s));
        c->setMapping(BodeController::Logarithmic);
    }

    void remeasure()
    {
        BodeController* c = bode();
        QVERIFY(c->pointCount() == 11);
        c->setCursorsOn(true);
        c->setCursorFrequency(1000);
        c->remeasureCursorPoint();
        QVERIFY(c->isRunning());
        QTRY_VERIFY_WITH_TIMEOUT(c->state() == InstrumentController::Idle, 5000);
        QCOMPARE(c->pointCount(), 11);
        QVERIFY(std::abs(c->readoutGainDb() + 3.01) < 0.05);
    }

    void pauseAndResume()
    {
        BodeController* c = bode();
        c->setSweepMode(BodeController::Fast);
        c->setStartFrequency(100);
        c->setStopFrequency(10000);
        c->setStepsPerDecade(10);   // 21 points
        c->run();
        QTRY_VERIFY_WITH_TIMEOUT(c->pointCount() >= 3, 10000);
        c->pause(u"Bode Analyzer paused — AI in use by Test"_s);
        QTRY_VERIFY_WITH_TIMEOUT(c->state() == InstrumentController::Paused, 5000);
        const int kept = c->pointCount();
        QVERIFY(kept < 21);
        c->resume();
        QTRY_VERIFY_WITH_TIMEOUT(c->state() == InstrumentController::Idle, 20000);
        QVERIFY2(!c->hasError(), qPrintable(c->errorText()));
        QCOMPARE(c->pointCount(), 21);
        // Strictly increasing frequencies: the resumed sweep continued where it stopped.
        const auto snapshot = c->gain()->snapshot();
        for (size_t i = 1; i < snapshot->size(); ++i)
            QVERIFY(snapshot->xAt(i) > snapshot->xAt(i - 1));
        c->resetSettings();
    }

private:
    QTemporaryDir m_dir;
};

QTEST_GUILESS_MAIN(TestBodeController)
#include "tst_bodecontroller.moc"
