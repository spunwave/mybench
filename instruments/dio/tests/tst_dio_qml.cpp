// Digital I/O panel QML (offscreen): the pattern picture buttons select the writer
// pattern and stay bound to the controller; only the settings of the chosen pattern are shown;
// the sample interval exists once (Reader card); the header radix sets the controller radix.
#include "diocontroller.h"
#include "panellayoutcheck.h"

#include <mybench/devicehub.h>
#include <mybench/offscreen.h>

#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QStandardPaths>
#include <QTest>

#include <functional>
#include <memory>

using namespace Qt::StringLiterals;
using mybench::instruments::DioController;

class TestDioQml : public QObject
{
    Q_OBJECT

    QQmlEngine m_engine;
    std::unique_ptr<mybench::OffscreenWindow> m_window;
    std::unique_ptr<QObject> m_root;
    std::unique_ptr<DioController> m_dio;   // outlives the panel (destroyed in cleanup())

    QObject* find(const QString& name) const
    {
        std::function<QObject*(QQuickItem*)> walk = [&](QQuickItem* item) -> QObject* {
            if (item->objectName() == name)
                return item;
            for (QQuickItem* child : item->childItems())
                if (QObject* found = walk(child))
                    return found;
            return nullptr;
        };
        auto* item = qobject_cast<QQuickItem*>(m_root.get());
        return item ? walk(item) : nullptr;
    }
    bool shown(const QString& name) const
    {
        auto* item = qobject_cast<QQuickItem*>(find(name));
        return item && item->isVisible();
    }
    void render()
    {
        for (int i = 0; i < 2; ++i) {
            m_window->renderFrame();
            QCoreApplication::processEvents();
        }
    }
    DioController& controller()
    {
        m_dio = std::make_unique<DioController>();
        m_dio->initialize();
        return *m_dio;
    }
    bool createPanel(DioController& ctr, QSize size = QSize(1440, 900))
    {
        m_window = std::make_unique<mybench::OffscreenWindow>(size);
        if (!m_window->isValid())
            return false;
        QQmlComponent component(&m_engine);
        component.setData("import QtQuick\nimport MyBench.Instruments.Dio\nDioPanel { }\n", QUrl());
        m_root.reset(component.beginCreate(m_engine.rootContext()));
        if (!m_root) {
            qWarning() << component.errorString();
            return false;
        }
        m_root->setProperty("controller", QVariant::fromValue(&ctr));
        component.completeCreate();
        m_window->setRootItem(qobject_cast<QQuickItem*>(m_root.get()));
        render();
        return true;
    }


    // Every object with a display title (the InstrumentPanel and its pane parts) shows none.
    static void verifyNoDisplayText(QObject* root)
    {
        int panels = 0;
        for (QObject* o : root->findChildren<QObject*>()) {
            if (o->metaObject()->indexOfProperty("displayTitle") < 0)
                continue;
            ++panels;
            QCOMPARE(o->property("displayTitle").toString(), QString());
            if (o->metaObject()->indexOfProperty("displayInfo") >= 0)
                QCOMPARE(o->property("displayInfo").toString(), QString());
        }
        QVERIFY(panels > 0);
    }

private slots:
    void initTestCase()
    {
        QStandardPaths::setTestModeEnabled(true);
        mybench::InstrumentController::setRestoreSavedSettings(false);
        mybench::DeviceHub::instance()->select(u"sim:0"_s);
        QTRY_VERIFY(mybench::DeviceHub::instance()->isConnected());
        m_engine.addImportPath(QStringLiteral(MYBENCH_QML_DIR));
    }
    void cleanup()
    {
        m_root.reset();
        m_window.reset();
        m_dio.reset();
    }

    // The seven target windows: the display's size, knobs in every row; and the line strip: eight
    // cells in one row, each at least 54 px wide.
    void targetWindows_data()
    {
        QTest::addColumn<int>("index");
        const auto panes = mybench::testing::targetPanes();
        for (int i = 0; i < panes.size(); ++i)
            QTest::newRow(qPrintable(panes.at(i).tag)) << i;
    }
    void targetWindows()
    {
        QFETCH(int, index);
        const mybench::testing::TargetPane target = mybench::testing::targetPanes().at(index);
        DioController& dio = controller();
        if (!createPanel(dio, target.pane))
            QSKIP("no graphics device");
        const QString error = mybench::testing::checkPane(qobject_cast<QQuickItem*>(m_root.get()), target);
        QVERIFY2(error.isEmpty(), qPrintable(target.tag + u": "_s + error));
        if (auto* shown = mybench::testing::findInstrumentPanel(qobject_cast<QQuickItem*>(m_root.get()))->property("displayArea").value<QQuickItem*>())
            qInfo().noquote() << "display" << target.tag << shown->width() << "x" << shown->height();
        qreal top = -1;
        for (int line = 0; line < 8; ++line) {
            auto* cell = qobject_cast<QQuickItem*>(find(u"dioLine%1"_s.arg(line)));
            QVERIFY(cell && cell->isVisible());
            QVERIFY2(cell->width() >= 54, qPrintable(u"cell %1 is %2 px wide"_s.arg(line).arg(cell->width())));
            const qreal y = cell->mapToScene(QPointF(0, 0)).y();
            if (top < 0)
                top = y;
            QCOMPARE(y, top);   // one row
        }
    }

    void patternButtonsAndSettings()
    {
        DioController& dio = controller();
        if (!createPanel(dio))
            QSKIP("no graphics device");
        QVERIFY(shown(u"dioWriterCard"_s));
        QVERIFY(shown(u"dioManualValue"_s));
        QVERIFY(!shown(u"dioStepInterval"_s));
        QObject* manual = find(u"dioPattern0"_s);
        QObject* ramp = find(u"dioPattern1"_s);
        QVERIFY(manual && ramp);
        QVERIFY(manual->property("checked").toBool());

        QMetaObject::invokeMethod(ramp, "clicked");
        render();
        QCOMPARE(dio.pattern(), DioController::Ramp);
        QVERIFY(ramp->property("checked").toBool());
        QVERIFY(!manual->property("checked").toBool());
        QVERIFY(shown(u"dioStepInterval"_s));
        QVERIFY(!shown(u"dioManualValue"_s));

        // The sample interval is edited in one place only.
        int intervals = 0;
        std::function<void(QQuickItem*)> walk = [&](QQuickItem* item) {
            if (item->objectName() == u"dioSampleInterval"_s)
                ++intervals;
            for (QQuickItem* child : item->childItems())
                walk(child);
        };
        walk(qobject_cast<QQuickItem*>(m_root.get()));
        QCOMPARE(intervals, 1);
    }

    void headerRadixSetsController()
    {
        DioController& dio = controller();
        if (!createPanel(dio))
            QSKIP("no graphics device");
        // The radix control lives in the pane header (InstrumentPanel.headerContent).
        QObject* radix = m_root->findChild<QObject*>(u"dioRadix"_s);
        if (!radix)
            radix = find(u"dioRadix"_s);
        QVERIFY(radix);
        QMetaObject::invokeMethod(radix, "activated", Q_ARG(int, 1));
        render();
        QCOMPARE(dio.outputRadix(), DioController::Binary);
        QCOMPARE(dio.inputRadix(), DioController::Binary);
        QCOMPARE(radix->property("currentIndex").toInt(), 1);
    }

    void lessText()
    {
        DioController& dio = controller();
        if (!createPanel(dio))
            QSKIP("no graphics device");
        // The line groups show once (the Lines card's Read / Write buttons): no display title or
        // info line, no card subtitles, no prose-only Timeline tool.
        verifyNoDisplayText(m_root.get());
        if (QTest::currentTestFailed())
            return;
        for (const QString& name : {u"dioLinesCard"_s, u"dioWriterCard"_s}) {
            QObject* card = find(name);
            QVERIFY2(card, qPrintable(name));
            QCOMPARE(card->property("subtitle").toString(), QString());
        }
        QVERIFY(!find(u"dioTimelinePanel"_s));
        QObject* tools = find(u"dioTools"_s);
        QVERIFY(tools);
        QCOMPARE(tools->property("model").toList().size(), 1);   // Labels (Export is the header's)
    }

    // One place per line. The line cell sets the direction (the Lines card keeps only the
    // Read / Write group shortcuts), shows High / Low and flips an output on a click in the
    // Manual pattern.
    void linesOnTheTiles()
    {
        DioController& dio = controller();
        if (!createPanel(dio))
            QSKIP("no graphics device");
        auto* linesCard = qobject_cast<QQuickItem*>(find(u"dioLinesCard"_s));
        QVERIFY(linesCard);
        int directionControls = 0;
        std::function<void(QQuickItem*)> walk = [&](QQuickItem* item) {
            if (item->objectName().startsWith(u"dioDirection"_s))
                ++directionControls;
            for (QQuickItem* child : item->childItems())
                walk(child);
        };
        walk(linesCard);
        QCOMPARE(directionControls, 0);
        walk(qobject_cast<QQuickItem*>(m_root.get()));
        QCOMPARE(directionControls, 16);   // input and output buttons in each of the 8 line cells

        // Direction from the cell: output button of line 5, then the same button again frees it.
        auto clickItem = [&](QQuickItem* item) {
            QVERIFY(item);
            QTest::mouseClick(m_window->window(), Qt::LeftButton, {}, item->mapToScene(QPointF(item->width() / 2, item->height() / 2)).toPoint());
            render();
        };
        auto* out5 = qobject_cast<QQuickItem*>(find(u"dioDirection5Out"_s));
        clickItem(out5);
        QVERIFY((dio.outputMask() >> 5) & 1);
        QVERIFY(out5->property("active").toBool());
        clickItem(out5);
        QVERIFY(!((dio.outputMask() >> 5) & 1));
        QVERIFY(!((dio.inputMask() >> 5) & 1));

        // An output cell toggles its line (Manual pattern).
        QCOMPARE(dio.pattern(), DioController::Manual);
        QObject* state0 = find(u"dioState0"_s);
        QVERIFY(state0);
        QVERIFY((dio.outputMask() >> 0) & 1);
        const int before = dio.manualValue();
        QVERIFY(QMetaObject::invokeMethod(find(u"dioLine0"_s), "activate"));
        render();
        QCOMPARE(dio.manualValue(), before ^ 1);
        QCOMPARE(find(u"dioLine0"_s)->property("level").toBool(), bool(dio.manualValue() & 1));
        // Review aid: MYBENCH_SHOT_DIR=<dir> saves the line strip with a High output.
        if (const QString dir = qEnvironmentVariable("MYBENCH_SHOT_DIR"); !dir.isEmpty())
            m_window->grab().save(dir + u"/dio-tiles.png"_s);
    }
};

QTEST_MAIN(TestDioQml)
#include "tst_dio_qml.moc"
