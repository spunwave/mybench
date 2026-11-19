// Geometric checks of an instrument pane for the QML tests: the seven target windows, the
// display's size, the aspect rule's choice (column or dock), knobs in every row, no clipped value,
// no sideways scrolling, and a display that no card or setting can resize.
//
//     using namespace mybench::testing;
//     for (const TargetPane& t : targetPanes()) {
//         create the panel with t.pane as the window size ...
//         const QString error = checkPane(panelRoot, t);       // empty = fine
//         QVERIFY2(error.isEmpty(), qPrintable(t.tag + ": " + error));
//     }
//     QVERIFY2(checkDisplayStable(panelRoot, render).isEmpty(), ...);
#pragma once

#include <QList>
#include <QPointF>
#include <QQuickItem>
#include <QRectF>
#include <QSizeF>
#include <QString>

#include <cmath>
#include <functional>

namespace mybench::testing {

// One of the seven target windows (pane size, not window size) and what the layout must give there.
struct TargetPane {
    QString tag;
    QSize pane;
    bool docked;          // the aspect rule's choice
    QSizeF display;       // the display's size in the table (checked down to 90 %)
};

inline QList<TargetPane> targetPanes()
{
    // Column 280 / 256 (pane under 1000 px). Docked height budget: the header's rows, the display
    // (at least 200 px and 45 % of what the header leaves), the dock clamp(0.35 x (pane - header),
    // 212, 320), the strip one row (two at most); the display takes the rest. Sizes are the
    // smallest the layout must give, checked down to 90 %.
    return {
        { QStringLiteral("single-1440"), QSize(1280, 824), false, QSizeF(1000, 700) },
        { QStringLiteral("single-1280"), QSize(1120, 724), false, QSizeF(840, 580) },
        { QStringLiteral("single-1024"), QSize(968, 624), false, QSizeF(712, 470) },
        { QStringLiteral("single-820"), QSize(764, 794), true, QSizeF(764, 340) },   // 360 with the default cards; 8 cards take a second compact row
        { QStringLiteral("split-1440"), QSize(640, 824), true, QSizeF(640, 350) },
        { QStringLiteral("split-1280"), QSize(612, 724), true, QSizeF(612, 280) },
        { QStringLiteral("split-1024"), QSize(484, 624), true, QSizeF(484, 200) },
    };
}

namespace detail {

inline bool isA(const QObject* object, const char* typeName)
{
    for (const QMetaObject* meta = object->metaObject(); meta; meta = meta->superClass()) {
        const QByteArray name(meta->className());
        if (name == typeName || name.startsWith(QByteArray(typeName) + "_QML"))
            return true;
    }
    return false;
}

inline void walk(QQuickItem* item, const std::function<void(QQuickItem*)>& visit)
{
    visit(item);
    for (QQuickItem* child : item->childItems())
        walk(child, visit);
}

inline QRectF sceneRect(const QQuickItem* item)
{
    return QRectF(item->mapToScene(QPointF(0, 0)), QSizeF(item->width(), item->height()));
}

}  // namespace detail

// The InstrumentPanel inside an instrument's root item (the one with the `docked` property).
inline QQuickItem* findInstrumentPanel(QQuickItem* root)
{
    QQuickItem* found = nullptr;
    detail::walk(root, [&](QQuickItem* item) {
        if (!found && item->property("hasControls").isValid() && item->property("docked").isValid())
            found = item;
    });
    return found;
}

// Checks the pane `root` (an instrument's root item laid out at t.pane): the aspect rule's choice,
// the display (the InstrumentPanel's DisplayArea) at 90 % of the table's size at least, a visible
// knob in every KnobField row, no clipped value, no Flickable that scrolls sideways. "" = fine.
inline QString checkPane(QQuickItem* root, const TargetPane& t)
{
    QQuickItem* panel = findInstrumentPanel(root);
    if (!panel)
        return QStringLiteral("no InstrumentPanel");
    if (panel->property("docked").toBool() != t.docked)
        return QStringLiteral("docked is %1, the table says %2").arg(panel->property("docked").toBool()).arg(t.docked);
    auto* display = panel->property("displayArea").value<QQuickItem*>();
    if (!display)
        return QStringLiteral("no display area");
    if (display->width() < 0.9 * t.display.width() || display->height() < 0.9 * t.display.height())
        return QStringLiteral("display %1 x %2, the table says %3 x %4 (down to 90 %)")
            .arg(display->width()).arg(display->height()).arg(t.display.width()).arg(t.display.height());
    if (display->width() < display->height())
        return QStringLiteral("display %1 x %2 is not landscape").arg(display->width()).arg(display->height());

    QString error;
    const QRectF paneRect = detail::sceneRect(root);
    detail::walk(root, [&](QQuickItem* item) {
        if (!error.isEmpty() || !item->isVisible())
            return;
        if (detail::isA(item, "KnobField") && item->property("form").toBool()) {   // the rows of cards
            auto* knob = item->property("knob").value<QQuickItem*>();
            if (!item->property("knobShown").toBool() || !knob || !knob->isVisible() || knob->width() < 20)
                error = QStringLiteral("no knob in the row of \"%1\" (%2 px wide)")
                            .arg(item->property("label").toString()).arg(item->width());
            else if (detail::sceneRect(knob).left() < paneRect.left() - 0.5 || detail::sceneRect(knob).right() > paneRect.right() + 0.5)
                error = QStringLiteral("the knob of \"%1\" is outside the pane").arg(item->property("label").toString());
            else if (item->width() < 190)
                error = QStringLiteral("the row of \"%1\" is %2 px wide, under the 190 px minimum")
                            .arg(item->property("label").toString()).arg(item->width());
            else {
                // The value is never clipped: the text fits its field.
                detail::walk(item, [&](QQuickItem* inner) {
                    if (error.isEmpty() && inner->objectName() == QLatin1String("valueInput") && inner->isVisible()
                        && inner->property("contentWidth").toReal() > inner->width() + 0.5)
                        error = QStringLiteral("the value of \"%1\" is clipped (%2 > %3)")
                                    .arg(item->property("label").toString())
                                    .arg(inner->property("contentWidth").toReal()).arg(inner->width());
                });
            }
        }
        // The measurement strip has its own check; leave its Flickable out here.
        bool inStrip = false;
        for (QQuickItem* p = item->parentItem(); p && !inStrip; p = p->parentItem())
            inStrip = detail::isA(p, "ScopeMeasurementCards") || detail::isA(p, "MeasurementStrip")
                      || p->objectName() == QLatin1String("measurementCards");
        if (error.isEmpty() && !inStrip && item->inherits("QQuickFlickable")
            && item->property("contentWidth").toReal() > item->width() + 0.5)
            error = QStringLiteral("a Flickable \"%3\" in \"%4\" scrolls sideways (%1 in %2)")
                        .arg(item->property("contentWidth").toReal()).arg(item->width()).arg(item->objectName(),
                             item->parentItem() ? QString::fromLatin1(item->parentItem()->metaObject()->className()) + item->parentItem()->objectName() : QString());
    });
    return error;
}

// Toggles every card of the control column / dock (ChannelCards with a switch) and checks that the
// display and the column keep their geometry, in the current layout. `render` shows a frame.
inline QString checkDisplayStable(QQuickItem* root, const std::function<void()>& render)
{
    QQuickItem* panel = findInstrumentPanel(root);
    if (!panel)
        return QStringLiteral("no InstrumentPanel");
    auto* display = panel->property("displayArea").value<QQuickItem*>();
    auto* column = panel->property("controlsColumn").value<QQuickItem*>();
    if (!display || !column)
        return QStringLiteral("no display or column");
    QList<QQuickItem*> cards;
    detail::walk(column, [&](QQuickItem* item) {
        if (detail::isA(item, "ChannelCard") && item->property("checkable").toBool() && item->property("host").isValid()
            && !item->property("host").isNull() && item->isVisible())
            cards.append(item);
    });
    if (cards.isEmpty())
        return QStringLiteral("no switchable card found");
    // The display's place and width never change; its height may only trade with the measurement
    // strip under it (the strip's height follows its cards, which is the strip's own rule): the
    // display and the strip together keep their height.
    QQuickItem* strip = nullptr;
    detail::walk(root, [&](QQuickItem* item) {
        if (item->objectName() == QLatin1String("stripHost"))
            strip = item;
    });
    const auto stripHeight = [&] { return strip && strip->isVisible() ? strip->height() : 0.0; };
    const QRectF displayBefore = detail::sceneRect(display);
    const double totalBefore = displayBefore.height() + stripHeight();
    const QRectF columnBefore = detail::sceneRect(column);
    for (QQuickItem* card : std::as_const(cards)) {
        for (int round = 0; round < 2; ++round) {
            const bool on = card->property("checked").toBool();
            QMetaObject::invokeMethod(card, "toggled", Q_ARG(bool, !on));
            render();
            const QRectF now = detail::sceneRect(display);
            if (now.topLeft() != displayBefore.topLeft() || now.width() != displayBefore.width()
                || std::abs(now.height() + stripHeight() - totalBefore) > 0.5)
                return QStringLiteral("switching \"%1\" resized the display (%2 x %3 -> %4 x %5)")
                    .arg(card->property("title").toString()).arg(displayBefore.width()).arg(displayBefore.height())
                    .arg(now.width()).arg(now.height());
            if (detail::sceneRect(column) != columnBefore)
                return QStringLiteral("switching \"%1\" resized the column").arg(card->property("title").toString());
        }
    }
    return {};
}

}  // namespace mybench::testing
