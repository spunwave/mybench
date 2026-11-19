// DMM panel layout (offscreen): display left, control column right, statistics
// cards at the bottom, at wide, split and narrow sizes.
#include "dmmcontroller.h"
#include "panellayoutcheck.h"

#include <mybench/devicehub.h>
#include <mybench/offscreen.h>

#include <QHash>
#include <QSet>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QStandardPaths>
#include <QTest>

#include <cmath>
#include <memory>

using namespace Qt::StringLiterals;
using mybench::instruments::DmmController;

class TestDmmQml : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase()
    {
        QStandardPaths::setTestModeEnabled(true);
        mybench::InstrumentController::setRestoreSavedSettings(false);
    }

    // The seven target windows: the display's size, a knob in every row, no clipped value, no
    // sideways scrolling; a function or range change never resizes the display.
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
        DmmController dmm;
        dmm.initialize();
        QQmlEngine engine;
        engine.addImportPath(QStringLiteral(MYBENCH_QML_DIR));
        mybench::OffscreenWindow offscreen(target.pane);
        if (!offscreen.isValid())
            QSKIP("no graphics device");
        QQmlComponent component(&engine);
        component.setData("import QtQuick\nimport MyBench.Instruments.Dmm\nDmmPanel { }\n", QUrl());
        std::unique_ptr<QObject> root(component.beginCreate(engine.rootContext()));
        QVERIFY2(root, qPrintable(component.errorString()));
        root->setProperty("controller", QVariant::fromValue(&dmm));
        component.completeCreate();
        auto* item = qobject_cast<QQuickItem*>(root.get());
        offscreen.setRootItem(item);
        for (int i = 0; i < 3; ++i)
            offscreen.renderFrame();
        const QString error = mybench::testing::checkPane(item, target);
        QVERIFY2(error.isEmpty(), qPrintable(target.tag + u": "_s + error));
        // The multimeter's cards have no switch: a function change must not resize the display.
        auto* panel = mybench::testing::findInstrumentPanel(item);
        auto* display = panel->property("displayArea").value<QQuickItem*>();
        const QRectF before(display->mapToScene(QPointF(0, 0)), QSizeF(display->width(), display->height()));
        for (auto function : {DmmController::AcVoltage, DmmController::Resistance, DmmController::Continuity, DmmController::DcCurrent}) {
            dmm.setSelectedFunction(function);
            offscreen.renderFrame();
            const QRectF after(display->mapToScene(QPointF(0, 0)), QSizeF(display->width(), display->height()));
            QVERIFY2(after == before, qPrintable(target.tag + u": the display changed with the function"_s));
        }
        offscreen.setRootItem(nullptr);
    }

    // Layout at wide, split and narrow sizes: the readout and the trend (display, left) never overlap
    // the control column (right); the function buttons, the trend plot and the statistics cards are
    // laid out inside the pane.
    void layoutAtSizes_data()
    {
        QTest::addColumn<QSize>("size");
        QTest::newRow("1440") << QSize(1440, 900);
        QTest::newRow("1000") << QSize(1000, 700);
        QTest::newRow("split") << QSize(640, 700);
        QTest::newRow("narrow") << QSize(420, 620);
    }

    void layoutAtSizes()
    {
        QFETCH(QSize, size);
        DmmController dmm;
        dmm.initialize();
        QQmlEngine engine;
        engine.addImportPath(QStringLiteral(MYBENCH_QML_DIR));
        mybench::OffscreenWindow offscreen(size);
        if (!offscreen.isValid())
            QSKIP("no graphics device");
        QQmlComponent component(&engine);
        component.setData("import QtQuick\nimport MyBench.Instruments.Dmm\nDmmPanel { }\n", QUrl());
        std::unique_ptr<QObject> root(component.beginCreate(engine.rootContext()));
        QVERIFY2(root, qPrintable(component.errorString()));
        root->setProperty("controller", QVariant::fromValue(&dmm));
        component.completeCreate();
        auto* item = qobject_cast<QQuickItem*>(root.get());
        QVERIFY(item);
        offscreen.setRootItem(item);
        offscreen.renderFrame();
        offscreen.renderFrame();

        const auto rectOf = [](QQuickItem* i) {
            return QRectF(i->mapToScene(QPointF(0, 0)), QSizeF(i->width(), i->height()));
        };
        const auto describe = [](const QRectF& r) {
            return u"%1,%2 %3x%4"_s.arg(r.x()).arg(r.y()).arg(r.width()).arg(r.height());
        };
        const QRectF pane(0, 0, item->width(), item->height());
        QHash<QString, QRectF> rects;
        for (const auto* name : {"dmmReadout", "instrumentColumn", "trendPlot", "functionGrid", "dmmStatistics", "dmmRunButton",
                                  "dmmResetStatistics"}) {
            auto* child = root->findChild<QQuickItem*>(QString::fromLatin1(name));
            QVERIFY2(child, name);
            // A display under 320 px gives all its height to the reading: no trend then.
            if (QLatin1StringView(name) == "trendPlot" && !child->isVisible())
                continue;
            QVERIFY2(child->isVisible(), name);
            const QRectF r = rectOf(child);
            QVERIFY2(r.width() > 0 && r.height() > 0, qPrintable(u"%1 not laid out: %2"_s.arg(QLatin1StringView(name), describe(r))));
            // The restart cell is the strip's last: in a narrow pane it sits in a row that scrolls vertically.
            auto* stripItem = root->findChild<QQuickItem*>(u"dmmStatistics"_s);
            const bool scrolled = QLatin1StringView(name) == "dmmResetStatistics" && stripItem->property("scrolls").toBool();
            QVERIFY2(scrolled || pane.adjusted(-0.5, -0.5, 0.5, 0.5).contains(r),
                     qPrintable(u"%1 outside the pane: %2"_s.arg(QLatin1StringView(name), describe(r))));
            rects.insert(QString::fromLatin1(name), r);
        }
        const QRectF controls = rects.value(u"instrumentColumn"_s);
        QVERIFY2(!rects.value(u"dmmReadout"_s).intersects(controls), qPrintable(describe(rects.value(u"dmmReadout"_s))));
        QVERIFY2(!rects.value(u"trendPlot"_s).intersects(controls), qPrintable(describe(rects.value(u"trendPlot"_s))));
        // The aspect rule: the column at the right, or the dock under the display.
        const bool band = mybench::testing::findInstrumentPanel(item)->property("docked").toBool();
        if (band)
            QVERIFY(rects.value(u"trendPlot"_s).bottom() <= controls.top() + 0.5);
        else
            QVERIFY(rects.value(u"trendPlot"_s).right() <= controls.left() + 0.5);
        QVERIFY(!rects.value(u"dmmReadout"_s).intersects(rects.value(u"trendPlot"_s)));
        // The reading takes the height the display gives it; the trend (when shown) starts under it.
        auto* block = root->findChild<QQuickItem*>(u"dmmReadoutBlock"_s);
        auto* trendView = root->findChild<QQuickItem*>(u"trendView"_s);
        QVERIFY(block && trendView);
        if (trendView->isVisible()) {
            const double gap = rectOf(trendView).top() - rectOf(block).bottom();
            QVERIFY2(gap >= -0.5 && gap <= 2 * 8 + 0.5, qPrintable(QString::number(gap)));
            QVERIFY2(trendView->height() >= 200 - 0.5, qPrintable(QString::number(trendView->height())));
        }
        if (size.height() >= 900) {
            auto* tools = root->findChild<QQuickItem*>(u"dmmTools"_s);
            QVERIFY(tools);
            const double tail = controls.bottom() - rectOf(tools).bottom();
            QVERIFY2(tail >= 0 && tail <= 3 * 8, qPrintable(QString::number(tail)));
        }

        // Function buttons stay in step with the controller after clicks (one checked button).
        auto* grid = root->findChild<QQuickItem*>(u"functionGrid"_s);
        QList<QQuickItem*> buttons;
        for (auto* child : grid->childItems()) {
            if (child->property("checkable").isValid() && child->metaObject()->indexOfMethod("click()") >= 0)
                buttons.append(child);
        }
        QCOMPARE(buttons.size(), 7);
        QVERIFY(QMetaObject::invokeMethod(buttons.at(1), "click"));      // AC V
        QCOMPARE(dmm.selectedFunction(), DmmController::AcVoltage);
        QVERIFY(QMetaObject::invokeMethod(buttons.at(0), "click"));      // DC V
        dmm.setSelectedFunction(DmmController::Resistance);              // key 5 / restore
        offscreen.renderFrame();
        int checkedCount = 0;
        for (auto* b : buttons)
            checkedCount += b->property("checked").toBool() ? 1 : 0;
        QCOMPARE(checkedCount, 1);
        QVERIFY(buttons.at(4)->property("checked").toBool());
        QVERIFY(QMetaObject::invokeMethod(buttons.at(4), "click"));      // the selected one again
        offscreen.renderFrame();
        QCOMPARE(dmm.selectedFunction(), DmmController::Resistance);
        QVERIFY2(buttons.at(4)->property("checked").toBool(), "clicking the selected function unchecked it");

        // The readout caption repeats no control: a fixed range is in the Range buttons, so it is
        // empty; the display has no function-name title (the function button says it).
        dmm.setAutoRange(false);
        offscreen.renderFrame();
        auto* readout = root->findChild<QQuickItem*>(u"dmmReadout"_s);
        QVERIFY(readout);
        QCOMPARE(readout->property("caption").toString().trimmed(), QString());
        auto* dmmPane = root->findChild<QQuickItem*>(u"dmmPane"_s);
        QVERIFY(dmmPane);
        QCOMPARE(dmmPane->property("displayTitle").toString(), QString());

        // A tool opens a panel floating over the display (never over the controls).
        auto* connections = root->findChild<QQuickItem*>(u"connectionsPanel"_s);
        QVERIFY(connections);
        QVERIFY(!connections->isVisible());
        root->setProperty("tool", u"connections"_s);
        offscreen.renderFrame();
        QVERIFY(connections->isVisible());
        const QRectF panelRect = rectOf(connections);
        QVERIFY2(panelRect.height() > 0, qPrintable(describe(panelRect)));
        // Over the display's right side in both layouts: left of the column, above the dock (the
        // cards and the palette are never covered).
        QVERIFY2(band ? panelRect.bottom() <= controls.top() + 0.5 : panelRect.right() <= controls.left() + 0.5,
                 qPrintable(describe(panelRect)));
        QVERIFY2(panelRect.left() >= -0.5, qPrintable(describe(panelRect)));
        // Review aid: MYBENCH_TEST_SHOT_DIR=<dir> saves the frame with the tool panel open.
        if (const QString dir = qEnvironmentVariable("MYBENCH_TEST_SHOT_DIR"); !dir.isEmpty())
            offscreen.grab().save(u"%1/%2-%3.png"_s.arg(dir, u"dmm-tool"_s, QString::fromLatin1(QTest::currentDataTag())));
        offscreen.setRootItem(nullptr);
    }

    // The column is the shared InstrumentColumn (fixed width, tools pinned); the ranges
    // are picture buttons with gauge pictograms whose labels fit, also with the 6 resistance
    // ranges in the compact column; Single works while measuring (stops after the next reading,
    // never a permanently grey button); the statistics restart is an icon named apart from the header ↺.
    void round5Controls_data()
    {
        QTest::addColumn<QSize>("size");
        QTest::newRow("1440") << QSize(1440, 900);
        QTest::newRow("compact") << QSize(900, 700);
    }

    void round5Controls()
    {
        QFETCH(QSize, size);
        mybench::DeviceHub::instance()->select(u"sim:0"_s);
        QTRY_VERIFY(mybench::DeviceHub::instance()->isConnected());
        DmmController dmm;
        dmm.initialize();
        QQmlEngine engine;
        engine.addImportPath(QStringLiteral(MYBENCH_QML_DIR));
        mybench::OffscreenWindow offscreen(size);
        if (!offscreen.isValid())
            QSKIP("no graphics device");
        QQmlComponent component(&engine);
        component.setData("import QtQuick\nimport MyBench.Instruments.Dmm\nDmmPanel { }\n", QUrl());
        std::unique_ptr<QObject> root(component.beginCreate(engine.rootContext()));
        QVERIFY2(root, qPrintable(component.errorString()));
        root->setProperty("controller", QVariant::fromValue(&dmm));
        component.completeCreate();
        auto* item = qobject_cast<QQuickItem*>(root.get());
        offscreen.setRootItem(item);
        offscreen.renderFrame();

        auto* column = root->findChild<QQuickItem*>(u"instrumentColumn"_s);
        auto* tools = root->findChild<QQuickItem*>(u"dmmTools"_s);
        QVERIFY(column && tools);
        if (!mybench::testing::findInstrumentPanel(item)->property("docked").toBool())
            QCOMPARE(column->width(), size.width() >= 1000 ? 280.0 : 256.0);
        QVERIFY(tools->parentItem());
        QCOMPARE(tools->parentItem()->objectName(), u"instrumentColumnTools"_s);

        // Ranges: picture buttons with a pictogram each, labels never elided.
        dmm.setSelectedFunction(DmmController::Resistance);
        offscreen.renderFrame();
        auto* grid = root->findChild<QQuickItem*>(u"rangeGrid"_s);
        QVERIFY(grid);
        QList<QQuickItem*> ranges;
        for (auto* child : grid->childItems())
            if (child->objectName().startsWith(u"range"_s))
                ranges.append(child);
        QCOMPARE(ranges.size(), dmm.rangeLabels().size() + 1);
        QVERIFY(ranges.size() >= 7);
        QSet<QString> glyphs;
        for (auto* button : std::as_const(ranges)) {
            const QString glyph = button->property("glyph").toString();
            QVERIFY2(!glyph.isEmpty(), qPrintable(button->property("text").toString()));
            glyphs.insert(glyph);
            const auto texts = button->findChildren<QQuickItem*>();
            for (auto* t : texts)
                if (t->property("truncated").isValid())
                    QVERIFY2(!t->property("truncated").toBool(), qPrintable(button->property("text").toString() + u" elided"_s));
        }
        QCOMPARE(glyphs.size(), ranges.size());   // one pictogram per range
        QVERIFY(QMetaObject::invokeMethod(ranges.at(2), "clicked"));
        QVERIFY(!dmm.autoRange());
        QCOMPARE(dmm.rangeIndex(), 1);
        offscreen.renderFrame();
        QVERIFY(ranges.at(2)->property("checked").toBool());
        QVERIFY(!ranges.at(0)->property("checked").toBool());
        QVERIFY(QMetaObject::invokeMethod(ranges.at(0), "clicked"));
        QVERIFY(dmm.autoRange());
        dmm.setSelectedFunction(DmmController::DcVoltage);

        // Statistics restart: an icon button with its own tooltip (the header ↺ resets settings).
        auto* restart = root->findChild<QQuickItem*>(u"dmmResetStatistics"_s);
        QVERIFY(restart);
        QCOMPARE(restart->property("toolTip").toString(), u"Reset Statistics"_s);

        // Single while measuring: enabled, and it ends the run after the next reading.
        auto* single = root->findChild<QQuickItem*>(u"dmmSingleButton"_s);
        QVERIFY(single);
        QVERIFY(single->isEnabled());
        dmm.run();
        QTRY_VERIFY_WITH_TIMEOUT(dmm.state() == mybench::InstrumentController::Running, 10000);
        offscreen.renderFrame();
        QVERIFY2(single->isEnabled(), "Single is grey while measuring");
        // The trend's time axis starts at the first reading and spans the run (≥ 10 s),
        // not the whole window with the trace squeezed at its right edge.
        {
            QObject* plot = root->findChild<QObject*>(u"trendPlot"_s);
            auto* xAxis = plot->property("xAxis").value<QObject*>();
            auto* buffer = dmm.property("trend").value<QObject*>();
            QTRY_VERIFY_WITH_TIMEOUT(buffer->property("count").toInt() >= 3, 10000);
            offscreen.renderFrame();
            double first = 0;
            QVERIFY(QMetaObject::invokeMethod(buffer, "xMinimum", Q_RETURN_ARG(double, first)));
            const double lo = xAxis->property("min").toDouble();
            const double hi = xAxis->property("max").toDouble();
            QVERIFY2(std::abs(lo - first) < 0.5, qPrintable(u"axis starts %1 s before the data"_s.arg(first - lo)));
            QVERIFY2(hi - lo <= 15, qPrintable(u"span %1 s for a few readings"_s.arg(hi - lo)));
        }
        // Hold and Relative: checked (accent, never filled) while on; Relative states its reference once.
        auto* hold = root->findChild<QQuickItem*>(u"dmmHoldButton"_s);
        auto* relative = root->findChild<QQuickItem*>(u"dmmRelativeButton"_s);
        QVERIFY(hold && relative);
        QVERIFY(!hold->property("checked").toBool());
        dmm.setHold(true);
        QVERIFY(hold->property("checked").toBool());
        dmm.setHold(false);
        dmm.setNullOffset(true);
        QVERIFY(relative->property("checked").toBool());
        QTRY_VERIFY_WITH_TIMEOUT(!dmm.nullArmed(), 10000);
        auto* caption = root->findChild<QQuickItem*>(u"dmmReadout"_s);
        QVERIFY(caption->property("caption").toString().contains(u"Δ from "_s + dmm.nullText()));
        dmm.setNullOffset(false);

        QVERIFY(QMetaObject::invokeMethod(single, "clicked"));
        QTRY_VERIFY_WITH_TIMEOUT(dmm.isIdle(), 15000);
        offscreen.setRootItem(nullptr);
    }
};

QTEST_MAIN(TestDmmQml)
#include "tst_dmm_qml.moc"
