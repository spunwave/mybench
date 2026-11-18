// Layout lint. Creates the real panel of every
// instrument against the simulator, in panes of many sizes, and walks the visual item tree
// generically (no per-instrument names) for overlaps, truncation, clipping, sideways scrolling,
// text that does not fit its control, a too small display and knob-less fields.
#include <mybench/devicehub.h>
#include <mybench/instrumentcontroller.h>
#include <mybench/instrumentregistry.h>
#include <mybench/offscreen.h>

#include <QDir>
#include <QFont>
#include <QFontDatabase>
#include <QFontInfo>
#include <QFontMetricsF>
#include <QGuiApplication>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQmlExpression>
#include <QQuickItem>
#include <QQuickStyle>
#include <QRegularExpression>
#include <QtMath>
#include <QSettings>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTest>
#include <QTextStream>

#include <algorithm>
#include <cstdio>
#include <functional>
#include <map>
#include <memory>
#include <set>
#include <atomic>
#include <chrono>
#include <mutex>
#include <thread>

#ifdef _WIN32
#include <process.h>
#else
#include <unistd.h>
#endif

using namespace Qt::StringLiterals;
using mybench::InstrumentController;
using mybench::InstrumentRegistry;

void registerBuiltInstruments(mybench::InstrumentRegistry& registry);   // generated, as in the app

namespace {

// ---- Item classification -----------------------------------------------------------------------

// A C++ base class by name (QQuickAbstractButton, QQuickText... are private headers).
bool inherits(const QObject* object, const char* cppClass)
{
    for (const QMetaObject* meta = object->metaObject(); meta; meta = meta->superClass())
        if (qstrcmp(meta->className(), cppClass) == 0)
            return true;
    return false;
}

// A QML type by name ("<Name>_QMLTYPE_<n>" or "<Name>_QML_<n>"), or a type derived from it.
bool isQml(const QObject* object, const char* qmlTypeName)
{
    for (const QMetaObject* meta = object->metaObject(); meta; meta = meta->superClass()) {
        const QByteArray name(meta->className());
        if (name == qmlTypeName || name.startsWith(QByteArray(qmlTypeName) + "_QML"))
            return true;
    }
    return false;
}

QString typeName(const QObject* object)
{
    for (const QMetaObject* meta = object->metaObject(); meta; meta = meta->superClass()) {
        QString name = QString::fromLatin1(meta->className());
        const int cut = name.indexOf(u"_QML"_s);
        if (cut > 0) {
            name = name.left(cut);
            return name.startsWith(u"QQuick"_s) ? name.mid(6) : name;
        }
        if (name.startsWith(u"QQuick"_s))
            return name.mid(6);
        if (!name.startsWith(u"Q"_s))
            return name;
    }
    return u"Item"_s;
}

bool isText(const QQuickItem* item) { return inherits(item, "QQuickText"); }
bool isTextInput(const QQuickItem* item) { return inherits(item, "QQuickTextInput") || inherits(item, "QQuickTextEdit"); }
bool isFlickable(const QQuickItem* item) { return inherits(item, "QQuickFlickable"); }
bool isButton(const QQuickItem* item) { return inherits(item, "QQuickAbstractButton"); }

// Visible controls the user can act on, and the app's composite ones.
bool isInteractive(const QQuickItem* item)
{
    static const char* const qmlTypes[] = {"Knob", "KnobField", "SegmentedControl", "StepSelector", "SiField",
                                           "MeasurementCard", "PictureButton", "ToggleSwitch"};
    static const char* const cppTypes[] = {"QQuickAbstractButton", "QQuickTextInput", "QQuickTextEdit", "QQuickComboBox",
                                           "QQuickSpinBox", "QQuickAbstractSlider"};
    for (const char* name : qmlTypes)
        if (isQml(item, name))
            return true;
    for (const char* name : cppTypes)
        if (inherits(item, name))
            return true;
    return false;
}

QString textOf(const QQuickItem* item) { return item->property("text").toString(); }
bool hasText(const QQuickItem* item) { return isText(item) && !textOf(item).trimmed().isEmpty(); }

// Text that may legitimately be cut: `property bool elideAllowed: true` on it or an ancestor.
bool elideAllowed(const QQuickItem* item)
{
    for (; item; item = item->parentItem())
        if (item->property("elideAllowed").toBool())
            return true;
    return false;
}

// What the user sees of an item: a Text is drawn at its content size inside its box.
QRectF paintedRect(const QQuickItem* item)
{
    if (!isText(item))
        return QRectF(0, 0, item->width(), item->height());
    const qreal contentWidth = item->property("contentWidth").toReal();
    const qreal contentHeight = item->property("contentHeight").toReal();
    const int horizontal = item->property("horizontalAlignment").toInt();
    const int vertical = item->property("verticalAlignment").toInt();
    qreal x = 0;
    if (horizontal == Qt::AlignRight)
        x = item->width() - contentWidth;
    else if (horizontal == Qt::AlignHCenter)
        x = (item->width() - contentWidth) / 2;
    qreal y = 0;
    if (vertical == Qt::AlignBottom)
        y = item->height() - contentHeight;
    else if (vertical == Qt::AlignVCenter)
        y = (item->height() - contentHeight) / 2;
    return QRectF(x, y, contentWidth, contentHeight);
}

// The item and its ancestors are shown: visible, not transparent, with a size.
bool shown(const QQuickItem* item) { return item->isVisible() && item->width() > 0 && item->height() > 0 && item->opacity() > 0.01; }

QString describeNoGeo(const QQuickItem* item)
{
    QString name = item->objectName();
    if (name.isEmpty()) {
        for (const char* property : {"text", "title", "label", "name"}) {
            QString value = item->property(property).toString().simplified();
            if (!value.isEmpty()) {
                name = value.left(28);
                break;
            }
        }
    }
    QString result = typeName(item);
    if (!name.isEmpty())
        result += u" \""_s + name + u'"';
    return result;
}

QString rectText(const QRectF& r)
{
    return u"[%1,%2 %3x%4]"_s.arg(qRound(r.x())).arg(qRound(r.y())).arg(qRound(r.width())).arg(qRound(r.height()));
}

// "Type "name" in Parent "name"" for items inside a named composite, to find them.
QString describeKey(const QQuickItem* item)
{
    QString result = describeNoGeo(item);
    for (const QQuickItem* p = item->parentItem(); p; p = p->parentItem()) {
        if (!p->objectName().isEmpty() || isInteractive(p)) {
            result += u" in "_s + describeNoGeo(p);
            break;
        }
    }
    return result;
}

// ---- Findings ------------------------------------------------------------------------------------

const QStringList kChecks = {u"header-overlap"_s, u"truncation"_s, u"clipping"_s, u"h-scroll"_s,
                             u"text-fit"_s, u"min-display"_s, u"knob-dropped"_s, u"sibling-overlap"_s, u"hang"_s};

struct Finding {
    QString instrument, mode, check, key, text;
    int width = 0, height = 0, step = 20, dir = 0;   // dir: 0 = the pane grew, 1 = it shrank
};

struct Context {
    QString instrument, mode;
    int width = 0, height = 0, step = 20, dir = 0;
};

class Sink
{
public:
    Context context;
    QList<Finding> findings;
    void add(const QString& check, const QString& key, const QString& text)
    {
        const QString full = u"%1|%2|%3x%4|%5|%6|%7"_s.arg(context.instrument, context.mode).arg(context.width).arg(context.height).arg(check, key).arg(context.dir);
        if (m_seen.contains(full))
            return;
        m_seen.insert(full);
        findings.append({context.instrument, context.mode, check, key, text, context.width, context.height, context.step, context.dir});
    }

private:
    QSet<QString> m_seen;
};

// ---- The lint ------------------------------------------------------------------------------------

constexpr qreal kTolerance = 1.0;

bool rectsOverlap(const QRectF& a, const QRectF& b)
{
    const QRectF i = a.intersected(b);
    return i.width() > kTolerance && i.height() > kTolerance;
}

bool containedIn(const QRectF& inner, const QRectF& outer, qreal tolerance)
{
    return inner.left() >= outer.left() - tolerance && inner.right() <= outer.right() + tolerance
           && inner.top() >= outer.top() - tolerance && inner.bottom() <= outer.bottom() + tolerance;
}

// Visible and drawn: not transparent, and not inside a clip without area (a parking item).
bool visibleItem(const QQuickItem* item)
{
    return item->isVisible() && item->opacity() > 0.01 && !(item->clip() && (item->width() <= 0 || item->height() <= 0));
}

// Visible items below `root` (not `root` itself), pre-order. An item without a size (a plain
// wrapper) is visible too: its children may be drawn.
void collectShown(QQuickItem* root, QList<QQuickItem*>& out)
{
    for (QQuickItem* child : root->childItems()) {
        if (!visibleItem(child))
            continue;
        out.append(child);
        collectShown(child, out);
    }
}

// The outermost "atoms" under `root`: interactive controls and texts, not looking inside controls.
void collectAtoms(QQuickItem* root, QList<QQuickItem*>& out)
{
    for (QQuickItem* child : root->childItems()) {
        if (!visibleItem(child))
            continue;
        if (shown(child) && (isInteractive(child) || hasText(child)))
            out.append(child);
        else
            collectAtoms(child, out);
    }
}

QRectF rectIn(const QQuickItem* space, const QQuickItem* item, const QRectF& local)
{
    return space->mapRectFromItem(item, local);
}

bool isAncestorOf(const QQuickItem* ancestor, const QQuickItem* item)
{
    for (const QQuickItem* p = item->parentItem(); p; p = p->parentItem())
        if (p == ancestor)
            return true;
    return false;
}

QQuickItem* findHeader(QQuickItem* pane)
{
    QList<QQuickItem*> all;
    collectShown(pane, all);
    for (QQuickItem* item : std::as_const(all))
        if (isQml(item, "PaneHeader"))
            return item;
    return nullptr;
}

// Widths of the texts a list-valued control can show, evaluated in its own QML context.
QStringList valueTexts(QQuickItem* control, const QString& script)
{
    QQmlExpression expression(qmlContext(control), control, script);
    const QVariant result = expression.evaluate();
    if (expression.hasError())
        return {};
    QStringList texts;
    for (const QVariant& entry : result.toList())
        texts.append(entry.toString());
    return texts;
}

void lintPane(QQuickItem* pane, QQuickItem* panel, Sink& sink)
{
    QList<QQuickItem*> all;
    collectShown(pane, all);
    QQuickItem* header = findHeader(pane);

    // a. Header: its atoms do not intersect each other and lie inside it.
    if (header) {
        QList<QQuickItem*> atoms;
        collectAtoms(header, atoms);
        const QRectF headerRect(0, 0, header->width(), header->height());
        QList<QRectF> rects;
        for (QQuickItem* atom : std::as_const(atoms))
            rects.append(rectIn(header, atom, paintedRect(atom)));
        for (int i = 0; i < atoms.size(); ++i) {
            if (!containedIn(rects[i], headerRect, kTolerance))
                sink.add(u"header-overlap"_s, describeKey(atoms[i]) + u" outside header"_s,
                         describeNoGeo(atoms[i]) + u' ' + rectText(rects[i]) + u" outside the header "_s
                             + rectText(headerRect));
            for (int j = i + 1; j < atoms.size(); ++j)
                if (rectsOverlap(rects[i], rects[j]))
                    sink.add(u"header-overlap"_s, describeKey(atoms[i]) + u" x "_s + describeKey(atoms[j]),
                             describeNoGeo(atoms[i]) + u' ' + rectText(rects[i]) + u" x "_s + describeNoGeo(atoms[j])
                                 + u' ' + rectText(rects[j]));
        }
    }

    for (QQuickItem* item : std::as_const(all)) {
        const bool real = shown(item);
        // b. Truncation.
        if (real && isText(item) && hasText(item) && !elideAllowed(item)) {
            const bool truncated = item->property("truncated").toBool();
            const qreal contentWidth = item->property("contentWidth").toReal();
            const bool noElide = item->property("elide").toInt() == Qt::ElideNone;
            const bool noWrap = item->property("wrapMode").toInt() == 0;
            const qreal need = item->implicitWidth();
            if (truncated)
                sink.add(u"truncation"_s, describeKey(item),
                         u"elided "_s + describeNoGeo(item) + u' ' + rectText(rectIn(pane, item, QRectF(0, 0, item->width(), item->height())))
                             + u" needs "_s + QString::number(qRound(need)) + u" px, has "_s + QString::number(qRound(item->width())));
            else if (noElide && noWrap && contentWidth > item->width() + 0.5)
                sink.add(u"truncation"_s, describeKey(item),
                         u"overflowing "_s + describeNoGeo(item) + u' ' + rectText(rectIn(pane, item, QRectF(0, 0, item->width(), item->height())))
                             + u" needs "_s + QString::number(qRound(contentWidth)) + u" px, has "_s + QString::number(qRound(item->width())));
        }

        // c. Clipping: controls inside every ancestor that clips. The rectangle is followed in pane
        // coordinates; a vertically scrolling Flickable only shows part of it (that part is what the
        // outer clips see), so only the width has to fit there.
        if (real && isInteractive(item)) {
            QRectF r = rectIn(pane, item, QRectF(0, 0, item->width(), item->height()));
            for (QQuickItem* ancestor = item->parentItem(); ancestor && ancestor != pane->parentItem(); ancestor = ancestor->parentItem()) {
                const bool flickable = isFlickable(ancestor);
                if (!flickable && !ancestor->clip())
                    continue;
                const QRectF viewport = rectIn(pane, ancestor, QRectF(0, 0, ancestor->width(), ancestor->height()));
                // Entirely above or below the viewport: collapsed or scrolled away, not cut.
                if (r.bottom() <= viewport.top() + 0.5 || r.top() >= viewport.bottom() - 0.5)
                    break;
                const bool scrollsVertically = flickable && ancestor->property("contentHeight").toReal() > ancestor->height() + 0.5;
                const bool horizontalOk = r.left() >= viewport.left() - 0.5 && r.right() <= viewport.right() + 0.5;
                const bool verticalOk = scrollsVertically || (r.top() >= viewport.top() - 0.5 && r.bottom() <= viewport.bottom() + 0.5);
                if (!horizontalOk || !verticalOk) {
                    sink.add(u"clipping"_s, describeKey(item) + u" cut by "_s + describeNoGeo(ancestor),
                             describeNoGeo(item) + u' ' + rectText(r) + u" cut by "_s + describeNoGeo(ancestor) + u' ' + rectText(viewport));
                    break;
                }
                if (scrollsVertically) {
                    r.setTop(std::max(r.top(), viewport.top()));
                    r.setBottom(std::min(r.bottom(), viewport.bottom()));
                }
            }
        }

        // d. No sideways scrolling.
        if (real && isFlickable(item)) {
            const qreal contentWidth = item->property("contentWidth").toReal();
            const int direction = item->property("flickableDirection").toInt();   // 2 = VerticalFlick
            if (contentWidth > item->width() + 0.5 && direction != 2 && item->property("interactive").toBool())
                sink.add(u"h-scroll"_s, describeKey(item),
                         describeNoGeo(item) + u' ' + rectText(rectIn(pane, item, QRectF(0, 0, item->width(), item->height())))
                             + u" content "_s + QString::number(qRound(contentWidth)) + u" px wide, viewport "_s
                             + QString::number(qRound(item->width())));
        }

        // g. Knobs are never dropped.
        if (real && isQml(item, "KnobField")) {
            auto* knob = qobject_cast<QQuickItem*>(item->property("knob").value<QObject*>());
            if (!knob || !shown(knob)) {
                QString why = !knob ? u"no knob item"_s
                              : !knob->isVisible() ? u"knob hidden (visible=false up to "_s + describeNoGeo(item) + u')'
                              : u"knob has no size or is transparent"_s;
                sink.add(u"knob-dropped"_s, describeKey(item),
                         describeNoGeo(item) + u' ' + rectText(rectIn(pane, item, QRectF(0, 0, item->width(), item->height()))) + u": "_s + why);
            }
        }

        // h. Siblings do not overlap (the header is covered by a.).
        if (!isQml(item, "PaneHeader") && !(header && (item == header || isAncestorOf(header, item)))) {
            QList<QQuickItem*> siblings;
            for (QQuickItem* child : item->childItems())
                if (shown(child) && (isInteractive(child) || hasText(child)))
                    siblings.append(child);
            for (int i = 0; i < siblings.size(); ++i)
                for (int j = i + 1; j < siblings.size(); ++j) {
                    if (!isInteractive(siblings[i]) && !isInteractive(siblings[j]))
                        continue;   // two texts: a label and its value may share a row, see a.
                    const QRectF a = paintedRect(siblings[i]).translated(siblings[i]->position());
                    const QRectF b = paintedRect(siblings[j]).translated(siblings[j]->position());
                    if (rectsOverlap(a, b))
                        sink.add(u"sibling-overlap"_s, describeKey(siblings[i]) + u" x "_s + describeKey(siblings[j]),
                                 describeNoGeo(siblings[i]) + u' ' + rectText(rectIn(pane, siblings[i], paintedRect(siblings[i])))
                                     + u" x "_s + describeNoGeo(siblings[j]) + u' '
                                     + rectText(rectIn(pane, siblings[j], paintedRect(siblings[j]))));
                }
        }
    }

    // e. Text inside its control: outermost controls only.
    QList<QQuickItem*> controls;
    collectAtoms(pane, controls);
    for (QQuickItem* control : std::as_const(controls)) {
        if (!isInteractive(control))
            continue;
        QList<QQuickItem*> inner;
        collectShown(control, inner);
        std::set<QQuickItem*> flagged;
        QList<QQuickItem*> inputs = isTextInput(control) ? QList<QQuickItem*>{control} : QList<QQuickItem*>();
        for (QQuickItem* item : std::as_const(inner))
            if (isTextInput(item) && shown(item))
                inputs.append(item);
        for (QQuickItem* input : std::as_const(inputs)) {
            const qreal available = input->width() - input->property("leftPadding").toReal() - input->property("rightPadding").toReal();
            const qreal need = input->property("contentWidth").toReal();
            if (need > available + 0.5) {
                flagged.insert(input);
                sink.add(u"text-fit"_s, describeKey(input),
                         describeNoGeo(input) + u' ' + rectText(rectIn(pane, input, QRectF(0, 0, input->width(), input->height())))
                             + u" text \""_s + input->property("text").toString() + u"\" needs "_s + QString::number(qRound(need))
                             + u" px, the field gives "_s + QString::number(qRound(available)) + u" px");
            }
        }
        const QRectF controlRect(0, 0, control->width(), control->height());
        QList<QQuickItem*> interactiveInner;
        for (QQuickItem* item : std::as_const(inner))
            if (shown(item) && isInteractive(item) && !isQml(item, "Knob"))
                interactiveInner.append(item);
        for (QQuickItem* item : std::as_const(inner)) {
            if (!shown(item) || !(hasText(item) || isTextInput(item)) || elideAllowed(item) || flagged.count(item))
                continue;
            QRectF painted = rectIn(control, item, paintedRect(item));
            if (isTextInput(item)) {
                const qreal contentWidth = item->property("contentWidth").toReal();
                painted = rectIn(control, item, QRectF((item->width() - contentWidth) / 2, 0, contentWidth, item->height()));
            }
            if (!containedIn(painted, controlRect, kTolerance))
                sink.add(u"text-fit"_s, describeKey(item) + u" outside "_s + describeNoGeo(control),
                         describeNoGeo(item) + u' ' + rectText(rectIn(pane, item, paintedRect(item))) + u" \""_s + textOf(item).left(24)
                             + u"\" sticks out of "_s + describeNoGeo(control) + u' '
                             + rectText(rectIn(pane, control, controlRect)));
            for (QQuickItem* other : std::as_const(interactiveInner)) {
                if (other == item || isAncestorOf(other, item) || isAncestorOf(item, other))
                    continue;
                if (rectsOverlap(painted, rectIn(control, other, QRectF(0, 0, other->width(), other->height()))))
                    sink.add(u"text-fit"_s, describeKey(item) + u" under "_s + describeNoGeo(other),
                             describeNoGeo(item) + u" \""_s + (isTextInput(item) ? item->property("text").toString() : textOf(item)).left(24)
                                 + u"\" "_s + rectText(rectIn(pane, item, paintedRect(item))) + u" runs under "_s + describeNoGeo(other)
                                 + u' ' + rectText(rectIn(pane, other, QRectF(0, 0, other->width(), other->height()))));
            }
        }
    }

    // e. (list controls) Every value the control can show fits the room it gives its text.
    for (QQuickItem* item : std::as_const(all)) {
        if (!shown(item))
            continue;
        if (isQml(item, "KnobField") && item->property("discrete").toBool()) {
            QQuickItem* input = nullptr;
            for (QQuickItem* candidate : std::as_const(all))
                if (isTextInput(candidate) && isAncestorOf(item, candidate)) {
                    input = candidate;
                    break;
                }
            if (!input)
                continue;
            const QStringList texts = valueTexts(item, u"(function(){var r=[];for(var i=0;i<count;++i)r.push(textOf(i,Number(values[i])));return r})()"_s);
            const qreal available = input->width() - input->property("leftPadding").toReal() - input->property("rightPadding").toReal();
            const QFontMetricsF metrics(input->property("font").value<QFont>());
            for (const QString& text : texts)
                if (metrics.horizontalAdvance(text) > available + 1.0) {
                    sink.add(u"text-fit"_s, describeKey(item) + u" value list"_s,
                             describeNoGeo(item) + u' ' + rectText(rectIn(pane, item, QRectF(0, 0, item->width(), item->height())))
                                 + u" value \""_s + text + u"\" needs "_s + QString::number(qCeil(metrics.horizontalAdvance(text)))
                                 + u" px, the field gives "_s + QString::number(qRound(available)) + u" px");
                    break;
                }
        } else if (isQml(item, "StepSelector")) {
            QQuickItem* text = nullptr;
            for (QQuickItem* candidate : std::as_const(all))
                if (isText(candidate) && isAncestorOf(item, candidate)) {
                    text = candidate;
                    break;
                }
            if (!text)
                continue;
            QQuickItem* button = nullptr;
            for (QQuickItem* p = text->parentItem(); p && p != item; p = p->parentItem())
                if (isButton(p)) {
                    button = p;
                    break;
                }
            if (!button)
                continue;
            const QStringList texts = valueTexts(item, u"(function(){var r=[];for(var i=0;i<count;++i)r.push(textAt(i));return r})()"_s);
            const qreal available = button->width() - (text->parentItem()->width() - text->width());
            const QFontMetricsF metrics(text->property("font").value<QFont>());
            for (const QString& entry : texts)
                if (metrics.horizontalAdvance(entry) > available + 1.0) {
                    sink.add(u"text-fit"_s, describeKey(item) + u" value list"_s,
                             describeNoGeo(item) + u' ' + rectText(rectIn(pane, item, QRectF(0, 0, item->width(), item->height())))
                                 + u" value \""_s + entry + u"\" needs "_s + QString::number(qCeil(metrics.horizontalAdvance(entry)))
                                 + u" px, the selector gives "_s + QString::number(qRound(available)) + u" px");
                    break;
                }
        } else if (isQml(item, "SiField") && item->property("steps").toList().size() > 0) {
            const QStringList texts = valueTexts(item, u"(function(){var r=[];for(var i=0;i<steps.length;++i)r.push(formatValue(Number(steps[i])));return r})()"_s);
            const qreal available = item->width() - item->property("leftPadding").toReal() - item->property("rightPadding").toReal();
            const QFontMetricsF metrics(item->property("font").value<QFont>());
            for (const QString& entry : texts)
                if (metrics.horizontalAdvance(entry) > available + 1.0) {
                    sink.add(u"text-fit"_s, describeKey(item) + u" value list"_s,
                             describeNoGeo(item) + u' ' + rectText(rectIn(pane, item, QRectF(0, 0, item->width(), item->height())))
                                 + u" value \""_s + entry + u"\" needs "_s + QString::number(qCeil(metrics.horizontalAdvance(entry)))
                                 + u" px, the field gives "_s + QString::number(qRound(available)) + u" px");
                    break;
                }
        }
    }

    // f. Minimum display: the panel's display AREA is 200 px each way (below). A plot inside it (an item whose
    // type ends in "Plot"; under 100 px wide or 40 px high: a sparkline, ignored) may be a secondary one
    // (the equalizer's response over its spectrum, a counter's trend under its reading): it only has to be
    // 200 px wide and 80 px high.
    for (QQuickItem* item : std::as_const(all)) {
        if (!shown(item) || !typeName(item).endsWith(u"Plot"_s) || item->width() < 100 || item->height() < 40)
            continue;
        if (item->width() < 200 - 0.5 || item->height() < 80 - 0.5)
            sink.add(u"min-display"_s, describeKey(item),
                     describeNoGeo(item) + u' ' + rectText(rectIn(pane, item, QRectF(0, 0, item->width(), item->height())))
                         + u" is under 200 px wide or 80 px high"_s);
    }
    if (auto* display = qobject_cast<QQuickItem*>(panel->property("displayArea").value<QObject*>())) {
        if (display->width() < 200 - 0.5 || display->height() < 200 - 0.5)
            sink.add(u"min-display"_s, u"display"_s,
                     u"display "_s + rectText(rectIn(pane, display, QRectF(0, 0, display->width(), display->height())))
                         + u" is under 200 px in one direction"_s);
    }
}

// All the visible geometry in one number: the layout is settled when it stops changing.
size_t layoutSignature(QQuickItem* root)
{
    size_t hash = 0;
    std::function<void(QQuickItem*)> walk = [&](QQuickItem* item) {
        for (QQuickItem* child : item->childItems()) {
            if (!child->isVisible())
                continue;
            const QPointF p = child->position();
            hash = hash * 1000003u ^ qHashMulti(0, qRound(p.x() * 4), qRound(p.y() * 4), qRound(child->width() * 4),
                                                qRound(child->height() * 4), qRound(child->opacity() * 10));
            walk(child);
        }
    };
    walk(root);
    return hash;
}

int envInt(const char* name, int fallback)
{
    const int value = qEnvironmentVariableIntValue(name);
    return value > 0 ? value : fallback;
}

QList<int> sweepWidths(int step)
{
    QList<int> widths;
    for (int w = envInt("LAYOUT_SWEEP_MIN_WIDTH", 440); w <= envInt("LAYOUT_SWEEP_MAX_WIDTH", 1320); w += step)
        widths.append(w);
    return widths;
}

}  // namespace

class TestLayoutSweep : public QObject
{
    Q_OBJECT

    QQmlEngine m_engine;
    std::unique_ptr<mybench::OffscreenWindow> m_window;
    Sink m_sink;
    QStringList m_ids;
    // Watchdog: a layout that never settles (a polish loop) freezes the thread. The step is
    // reported as a finding of the check "hang" and the run ends.
    std::atomic<qint64> m_progress{0};
    std::atomic<bool> m_done{false};
    std::mutex m_stepMutex;
    Context m_step;

    void startWatchdog()
    {
        std::thread([this] {
            qint64 seen = -1;
            auto since = std::chrono::steady_clock::now();
            while (!m_done) {
                std::this_thread::sleep_for(std::chrono::milliseconds(250));
                if (m_progress != seen) {
                    seen = m_progress;
                    since = std::chrono::steady_clock::now();
                } else if (std::chrono::steady_clock::now() - since > std::chrono::seconds(20)) {
                    Context step;
                    {
                        std::lock_guard<std::mutex> lock(m_stepMutex);
                        step = m_step;
                    }
                    m_sink.context = step;
                    m_sink.add(u"hang"_s, u"layout never settles"_s,
                               u"the layout does not settle (a polish or binding loop keeps the UI thread busy): the sweep stops here"_s);
                    report(m_ids);
                    std::fflush(stdout);
                    _exit(1);
                }
            }
        }).detach();
    }
    void markStep(const Context& context)
    {
        {
            std::lock_guard<std::mutex> lock(m_stepMutex);
            m_step = context;
        }
        ++m_progress;
    }

    struct Pane {
        std::unique_ptr<QQuickItem> root;   // the window's root
        QQuickItem* pane = nullptr;         // clips, sized to the pane
        std::unique_ptr<QObject> panelObject;
        QQuickItem* panel = nullptr;
    };

    // The panel is created at its first size (as when the shell opens a pane), then resized by the sweep.
    bool createPane(const QString& id, Pane& pane, QSize size, bool closable)
    {
        InstrumentRegistry* registry = InstrumentRegistry::instance();
        const QString instrumentId = id.section(u'/', 0, 0);
        const mybench::InstrumentDescriptor* descriptor = registry->descriptor(instrumentId);
        if (!descriptor)
            return false;
        InstrumentController* controller = registry->controller(instrumentId);
        QUrl url = id.contains(u'/') ? descriptor->viewUrl(id) : descriptor->panelUrl();
        if (url.isEmpty() && id == u"gen/editor"_s) {   // the generator's editor is a tab of its panel
            url = descriptor->panelUrl();
            controller->setProperty("activeTab", 1);
        }
        QQmlComponent component(&m_engine, url);
        for (int i = 0; i < 1000 && component.isLoading(); ++i)
            QTest::qWait(10);
        if (component.isError()) {
            qWarning().noquote() << component.errorString();
            return false;
        }
        pane.root = std::make_unique<QQuickItem>();
        pane.pane = new QQuickItem(pane.root.get());
        pane.pane->setClip(true);
        pane.pane->setSize(QSizeF(size));
        m_window->setRootItem(pane.root.get(), false);
        pane.root->setSize(QSizeF(m_window->size()));
        pane.panelObject.reset(component.beginCreate(m_engine.rootContext()));
        pane.panel = qobject_cast<QQuickItem*>(pane.panelObject.get());
        if (!pane.panel) {
            qWarning().noquote() << component.errorString();
            return false;
        }
        pane.panel->setProperty("controller", QVariant::fromValue(controller));
        pane.panel->setProperty("focused", true);
        pane.panel->setProperty("closable", closable);   // the split's pane: header with the close x
        pane.panel->setParentItem(pane.pane);
        pane.panel->setSize(QSizeF(size));
        component.completeCreate();
        return true;
    }

    void resizePane(Pane& pane, int width, int height)
    {
        pane.pane->setSize(QSizeF(width, height));
        pane.panel->setSize(QSizeF(width, height));
    }

    void settle(Pane& pane)
    {
        size_t last = 0;
        int stable = 0;
        for (int i = 0; i < 30 && stable < 2; ++i) {
            m_window->renderFrame();
            QCoreApplication::processEvents();
            QCoreApplication::sendPostedEvents(nullptr, QEvent::DeferredDelete);
            const size_t now = layoutSignature(pane.pane);
            stable = (i > 0 && now == last) ? stable + 1 : 0;
            last = now;
        }
    }

    // One sweep of a pane: every width of `widths` at every height of `heights`. Layouts depend on
    // how a pane got its size (a pane opened narrow and then widened is not the pane opened wide), so a
    // fresh panel is swept growing (from the narrowest width) and another one shrinking (from the widest).
    void sweep(const QString& id, const QString& mode, const QList<int>& widths, int step, const QList<int>& heights,
               bool closable = false)
    {
        const bool trace = qEnvironmentVariableIsSet("LAYOUT_SWEEP_TRACE");
        // LAYOUT_SWEEP_SHOTS=<dir>: a PNG of the pane at every size that has a finding (or every size
        // with LAYOUT_SWEEP_SHOTS_ALL=1), named <instrument>-<mode>-<direction>-<W>x<H>.png.
        const QString shotDir = qEnvironmentVariable("LAYOUT_SWEEP_SHOTS");
        const bool shotAll = qEnvironmentVariableIsSet("LAYOUT_SWEEP_SHOTS_ALL");
        const QString direction = qEnvironmentVariable("LAYOUT_SWEEP_DIR");   // up | down | (both)
        for (const char* dirName : {"up", "down"}) {
            if (!direction.isEmpty() && direction != QLatin1String(dirName))
                continue;
            const bool up = qstrcmp(dirName, "up") == 0;
            QList<int> order = widths;
            if (!up)
                std::reverse(order.begin(), order.end());
            for (int height : heights) {
                Pane pane;
                markStep({id, mode, 0, 0, step});
                QVERIFY2(createPane(id, pane, QSize(order.first(), height), closable), qPrintable(u"cannot create the panel of "_s + id));
                for (int width : order) {
                    if (trace)
                        std::fprintf(stderr, "layout-sweep %s %s %s %dx%d\n", qPrintable(id), qPrintable(mode), dirName, width, height);
                    markStep({id, mode, width, height, step});
                    resizePane(pane, width, height);
                    settle(pane);
                    m_sink.context = {id, mode, width, height, step, up ? 0 : 1};
                    const qsizetype before = m_sink.findings.size();
                    lintPane(pane.pane, pane.panel, m_sink);
                    if (!shotDir.isEmpty() && (m_sink.findings.size() > before || shotAll)) {
                        m_window->renderFrame();
                        const QImage image = m_window->grab();
                        if (!image.isNull()) {
                            QDir().mkpath(shotDir);
                            image.copy(0, 0, width, height)
                                .save(u"%1/%2-%3-%4-%5x%6.png"_s.arg(shotDir, QString(id).replace(u'/', u'_'), mode, QString::fromLatin1(dirName))
                                          .arg(width).arg(height));
                        }
                    }
                }
                pane.panel->setParentItem(nullptr);
                pane.panelObject.reset();
                QCoreApplication::sendPostedEvents(nullptr, QEvent::DeferredDelete);
            }
        }
        if (id == u"gen/editor"_s)
            InstrumentRegistry::instance()->controller(u"gen"_s)->setProperty("activeTab", 0);
    }

    static QString line(const Finding& f, int lo, int hi, const QList<int>& heights)
    {
        QString size = lo == hi ? QString::number(lo) : u"%1-%2"_s.arg(lo).arg(hi);
        QStringList hs;
        for (int h : heights)
            hs << QString::number(h);
        QString inst = f.instrument + (f.mode == u"stopped"_s ? QString() : u'(' + f.mode + u')');
        return u"%1 %2x%3 %4: %5"_s.arg(inst, size, hs.join(u'/'), f.check, f.text);
    }

    void report(const QStringList& instruments)
    {
        QTextStream out(stdout);
        const int cap = qEnvironmentVariableIntValue("LAYOUT_SWEEP_MAX") > 0 ? qEnvironmentVariableIntValue("LAYOUT_SWEEP_MAX") : 40;
        // group: (instrument, mode, check, key) -> height -> width -> text and the directions that found it
        struct Group {
            Finding first;
            std::map<int, std::map<int, std::pair<QString, int>>> byHeight;
        };
        std::map<std::tuple<QString, QString, QString, QString>, Group> groups;
        for (const Finding& f : std::as_const(m_sink.findings)) {
            Group& g = groups[{f.instrument, f.mode, f.check, f.key}];
            if (g.byHeight.empty())
                g.first = f;
            auto& entry = g.byHeight[f.height][f.width];
            entry.first = f.text;
            entry.second |= 1 << f.dir;
        }
        std::map<QString, std::map<QString, int>> table;
        std::map<QString, QList<std::pair<QString, QString>>> lines;   // sort key, line
        for (const auto& [key, group] : groups) {
            const Finding& f = group.first;
            // Widths found by both directions, or only when the pane grew (1) or shrank (2); runs of
            // consecutive widths per height, then heights with the same run merged into one line.
            for (const int directions : {3, 1, 2}) {
                std::map<std::pair<int, int>, std::pair<QList<int>, QString>> merged;
                for (const auto& [height, widths] : group.byHeight) {
                    int lo = -1, prev = -1;
                    QString text;
                    auto flush = [&] {
                        if (lo < 0)
                            return;
                        auto& entry = merged[{lo, prev}];
                        entry.first.append(height);
                        if (entry.second.isEmpty())
                            entry.second = text;
                    };
                    for (const auto& [width, t] : widths) {
                        if (t.second != directions)
                            continue;
                        if (lo >= 0 && width - prev <= f.step) {
                            prev = width;
                            continue;
                        }
                        flush();
                        lo = prev = width;
                        text = t.first;
                    }
                    flush();
                }
                for (const auto& [range, entry] : merged) {
                    Finding shown = f;
                    shown.text = entry.second + (directions == 1 ? u"  [only after the pane grew]"_s
                                                  : directions == 2 ? u"  [only after the pane shrank]"_s : QString());
                    lines[f.instrument].append({u"%1|%2|%3|%4"_s.arg(kChecks.indexOf(f.check), 2, 10, QLatin1Char('0')).arg(f.key).arg(range.first, 5, 10, QLatin1Char('0')).arg(f.mode),
                                                line(shown, range.first, range.second, entry.first)});
                    table[f.instrument][f.check]++;
                }
            }
        }
        out << "\n==== layout sweep findings ====\n";
        for (const QString& instrument : instruments) {
            auto& list = lines[instrument];
            std::sort(list.begin(), list.end());
            const int shownCount = std::min(int(list.size()), cap);
            for (int i = 0; i < shownCount; ++i)
                out << list[i].second << '\n';
            if (list.size() > shownCount)
                out << instrument << ": ... " << (list.size() - shownCount) << " more finding lines (LAYOUT_SWEEP_MAX=" << list.size() << ")\n";
        }
        out << "\n==== summary: finding lines per instrument and check ====\n";
        out << QString(u"%1"_s).arg(u"instrument"_s, -12);
        for (const QString& c : kChecks)
            out << QString(u"%1"_s).arg(c, -16);
        out << "total\n";
        for (const QString& instrument : instruments) {
            int total = 0;
            out << QString(u"%1"_s).arg(instrument, -12);
            for (const QString& c : kChecks) {
                const int n = table[instrument][c];
                total += n;
                out << QString(u"%1"_s).arg(n, -16);
            }
            out << total << '\n';
        }
        out.flush();
    }

private slots:
    void initTestCase()
    {
        QStandardPaths::setTestModeEnabled(true);
        mybench::InstrumentController::setRestoreSavedSettings(false);
        m_engine.addImportPath(QStringLiteral(MYBENCH_QML_DIR));
        m_window = std::make_unique<mybench::OffscreenWindow>(QSize(1400, 900));
        if (!m_window->isValid())
            QSKIP("no graphics device for the offscreen window");
        mybench::DeviceHub::instance()->select(u"sim:0"_s);
        QTRY_VERIFY(mybench::DeviceHub::instance()->isConnected());
        // Light theme, no animations (the layout settles at once).
        QQmlComponent component(&m_engine);
        component.setData("import QtQuick\nimport MyBench.Controls\nQtObject { Component.onCompleted: { Theme.mode = \"light\"; Theme.animations = false } }\n", QUrl());
        std::unique_ptr<QObject> setup(component.create());
        QVERIFY2(setup, qPrintable(component.errorString()));
    }

    // The lint finds what it claims to find: a scene with one known defect per check.
    void selfTest()
    {
        if (qEnvironmentVariable("LAYOUT_SWEEP") != u"selftest"_s)
            QSKIP("only with LAYOUT_SWEEP=selftest");
        QQmlComponent component(&m_engine);
        component.setData(R"(
            import QtQuick
            import QtQuick.Controls
            import MyBench.Controls
            Item {
                id: root
                width: 400; height: 400
                property Item displayArea: Item { parent: root; width: 120; height: 120 }
                Item {
                    Button { x: 0; y: 0; width: 80; height: 30; text: "One" }
                    Button { x: 40; y: 0; width: 80; height: 30; text: "Two" }
                }
                Text { y: 60; width: 30; text: "A very long text"; elide: Text.ElideRight }
                Item { y: 100; width: 100; height: 40; clip: true; Button { x: 60; width: 80; height: 30; text: "Cut" } }
                Flickable { y: 150; width: 100; height: 40; contentWidth: 300; contentHeight: 40 }
                TextInput { y: 200; width: 30; height: 20; text: "long long long text" }
                KnobField { y: 240; compact: true; values: [1, 2]; labels: ["1", "2"] }
            }
        )", QUrl());
        std::unique_ptr<QObject> object(component.create());
        QVERIFY2(object, qPrintable(component.errorString()));
        auto* root = qobject_cast<QQuickItem*>(object.get());
        Sink sink;
        sink.context = {u"selftest"_s, u"stopped"_s, 400, 400, 20};
        lintPane(root, root, sink);
        QSet<QString> found;
        for (const Finding& f : std::as_const(sink.findings))
            found.insert(f.check);
        for (const QString& check : {u"truncation"_s, u"clipping"_s, u"h-scroll"_s, u"text-fit"_s, u"knob-dropped"_s,
                                     u"sibling-overlap"_s, u"min-display"_s})
            QVERIFY2(found.contains(check), qPrintable(u"the lint misses check "_s + check));
    }

    void sweepPanels()
    {
        if (qEnvironmentVariable("LAYOUT_SWEEP") == u"selftest"_s)
            QSKIP("selftest only");
        InstrumentRegistry* registry = InstrumentRegistry::instance();
        QStringList ids;
        const QString requested = qEnvironmentVariable("LAYOUT_SWEEP");
        if (requested.isEmpty() || requested == u"all"_s) {
            ids = registry->ids();
            for (const QString& id : registry->ids())
                for (const mybench::ViewDescriptor& view : registry->descriptor(id)->views)
                    ids.append(view.id);
            if (ids.contains(u"gen"_s) && !ids.contains(u"gen/editor"_s))
                ids.append(u"gen/editor"_s);
        } else {
            ids = requested.split(QRegularExpression(u"[,; ]+"_s), Qt::SkipEmptyParts);
        }
        const int step = qEnvironmentVariableIntValue("LAYOUT_SWEEP_STEP") > 0 ? qEnvironmentVariableIntValue("LAYOUT_SWEEP_STEP") : 20;
        const int runningStep = std::max(80, step);
        QList<int> heights = {560, 700, 824};
        if (envInt("LAYOUT_SWEEP_HEIGHT", 0) > 0)
            heights = {envInt("LAYOUT_SWEEP_HEIGHT", 0)};

        m_ids = ids;
        startWatchdog();
        for (const QString& id : std::as_const(ids)) {
            if (!registry->contains(id.section(u'/', 0, 0))) {
                qWarning() << "unknown instrument" << id;
                continue;
            }
            sweep(id, u"stopped"_s, sweepWidths(step), step, heights);
            sweep(id, u"split"_s, sweepWidths(step), step, {700}, true);   // a split pane has the close x
            if (id == u"scope"_s) {
                QQmlComponent component(&m_engine);
                component.setData("import QtQuick\nimport MyBench.Controls\nQtObject { Component.onCompleted: Theme.mode = \"dark\" }\n", QUrl());
                std::unique_ptr<QObject> dark(component.create());
                sweep(id, u"dark"_s, sweepWidths(runningStep), runningStep, {700});
                component.setData("import QtQuick\nimport MyBench.Controls\nQtObject { Component.onCompleted: Theme.mode = \"light\" }\n", QUrl());
                std::unique_ptr<QObject> light(component.create());
            }
            if (id.contains(u'/'))
                continue;   // a secondary view shares its instrument's controller: stopped only
            InstrumentController* controller = registry->controller(id);
            controller->run();
            QTest::qWait(600);
            if (controller->isRunning()) {
                sweep(id, u"running"_s, sweepWidths(runningStep), runningStep, heights);
                controller->stop();
                QTest::qWait(300);
            } else {
                qWarning().noquote() << id << "does not run against the simulator: running sweep skipped";
            }
        }
        m_done = true;
        report(ids);
        QVERIFY2(m_sink.findings.isEmpty(), qPrintable(u"%1 layout findings, see the list above"_s.arg(m_sink.findings.size())));
    }
};

int main(int argc, char* argv[])
{
    if (qEnvironmentVariableIsEmpty("QT_QPA_PLATFORM"))
        qputenv("QT_QPA_PLATFORM", "offscreen");
    qputenv("MYBENCH_NO_USB", "1");
    QGuiApplication app(argc, argv);
    // As the app does offscreen: 13 px UI font, MyBench.Style, settings in a throw-away folder.
    QFont font = QGuiApplication::font();
    font.setPixelSize(13);
    if (!QFontDatabase::hasFamily(font.family()))
        font.setFamily(QFontInfo(font).family());
    QGuiApplication::setFont(font);
    QQuickStyle::setStyle(u"MyBench.Style"_s);
    QTemporaryDir settingsFolder;
    QSettings::setDefaultFormat(QSettings::IniFormat);
    QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, settingsFolder.path());
    QCoreApplication::setOrganizationName(u"MYBENCH layout lint"_s);
    QCoreApplication::setApplicationName(u"layout-sweep"_s);
    mybench::InstrumentRegistry::instance();
    registerBuiltInstruments(*InstrumentRegistry::instance());
    TestLayoutSweep test;
    const int result = QTest::qExec(&test, argc, argv);
    InstrumentRegistry::instance()->shutdown();
    return result;
}

#include "tst_layout_sweep.moc"
