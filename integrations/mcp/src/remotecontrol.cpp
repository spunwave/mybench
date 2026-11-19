#include "remotecontrol.h"

#include "mcpcommon.h"

#include <mybench/appinfo.h>
#include <mybench/devicehub.h>
#include <mybench/eventlog.h>
#include <mybench/instrumentcontroller.h>
#include <mybench/instrumentregistry.h>
#include <mybench/plot/tracebuffer.h>
#include <mybench/settingsjson.h>

#include <QBuffer>
#include <QElapsedTimer>
#include <QGuiApplication>
#include <QImage>
#include <QJsonDocument>
#include <QMetaEnum>
#include <QPointer>
#include <QQuickWindow>
#include <QRegularExpression>
#include <QTimer>
#include <QUrl>

#include <algorithm>
#include <cmath>

using namespace Qt::StringLiterals;

namespace mybench::mcp {

namespace {

constexpr int kMaxListItems = 64;   // longer readings (peak lists, octave bands) are cut

QString instrumentIds()
{
    return InstrumentRegistry::instance()->ids().join(u", "_s);
}

bool isObjectPointer(const QMetaProperty& property)
{
    return property.metaType().flags().testFlag(QMetaType::PointerToQObject);
}

QJsonValue limited(QJsonValue value)
{
    if (value.isArray() && value.toArray().size() > kMaxListItems) {
        QJsonArray cut;
        const QJsonArray all = value.toArray();
        for (int i = 0; i < kMaxListItems; ++i)
            cut.append(all.at(i));
        return cut;
    }
    if (value.isDouble() && !std::isfinite(value.toDouble()))
        return QJsonValue::Null;
    return value;
}

QJsonValue readValue(const QObject* owner, const QMetaProperty& property)
{
    QJsonValue value = json::readProperty(owner, property);
    if (value.isUndefined()) {
        const QVariant raw = property.read(owner);
        if (raw.typeId() == QMetaType::Double && !std::isfinite(raw.toDouble()))
            return QJsonValue::Null;
        if (raw.typeId() == QMetaType::QDateTime)
            return raw.toDateTime().isValid() ? QJsonValue(raw.toDateTime().toString(Qt::ISODate)) : QJsonValue::Null;
        value = QJsonValue::fromVariant(raw);
    }
    return limited(value);
}

QJsonArray enumKeys(const QMetaProperty& property)
{
    QJsonArray keys;
    if (!property.isEnumType())
        return keys;
    const QMetaEnum meta = property.enumerator();
    for (int i = 0; i < meta.keyCount(); ++i)
        keys.append(QString::fromLatin1(meta.key(i)));
    return keys;
}

// The base InstrumentController properties worth reporting with the readings.
const QStringList& baseReadings()
{
    static const QStringList names{u"state"_s,        u"runMode"_s,     u"statusText"_s, u"summary"_s,
                                   u"keyValue"_s,     u"errorText"_s,   u"inputWarning"_s, u"pauseReason"_s,
                                   u"acquisitionCount"_s, u"sampleRate"_s, u"holdsOutputs"_s};
    return names;
}

void collect(QObject* object, const QString& prefix, int depth, int firstProperty, RemoteControl::Inventory& out)
{
    const QMetaObject* meta = object->metaObject();
    for (int i = firstProperty; i < meta->propertyCount(); ++i) {
        const QMetaProperty property = meta->property(i);
        const QString name = QString::fromLatin1(property.name());
        if (name == u"objectName"_s)
            continue;
        const QString path = prefix + name;
        if (isObjectPointer(property)) {
            QObject* child = property.read(object).value<QObject*>();
            if (!child)
                continue;
            const QString className = QString::fromLatin1(child->metaObject()->className());
            if (qobject_cast<plot::TraceBuffer*>(child))
                out.traces.append({object, property, path});
            else if (depth < 2 && !className.contains(u"Style"_s) && !className.contains(u"Buffer"_s)
                     && !className.contains(u"Editor"_s))
                collect(child, path + u'.', depth + 1, 1, out);
            continue;
        }
        // Lists of labels and steps ("scaleLabels", "timeDivValues") describe choices, not readings.
        const bool choices = name.endsWith(u"Labels"_s) || name.endsWith(u"Values"_s) || name.endsWith(u"Catalog"_s);
        if (RemoteControl::isRemoteWritable(property))
            out.settings.append({object, property, path});
        else if (property.isConstant() || choices)
            out.constants.append({object, property, path});
        else
            out.readings.append({object, property, path});
    }
}

// Resolves "channel0.voltsPerDiv" to its owner object and property.
bool resolve(QObject* root, const QString& path, QObject** owner, QMetaProperty* property)
{
    const QStringList parts = path.split(u'.');
    QObject* object = root;
    for (qsizetype i = 0; i < parts.size(); ++i) {
        const QMetaObject* meta = object->metaObject();
        const int index = meta->indexOfProperty(parts[i].toUtf8().constData());
        if (index < 0)
            return false;
        const QMetaProperty p = meta->property(index);
        if (i + 1 == parts.size()) {
            *owner = object;
            *property = p;
            return true;
        }
        if (!isObjectPointer(p))
            return false;
        object = p.read(object).value<QObject*>();
        if (!object)
            return false;
    }
    return false;
}

// Enum names are matched without regard to case ("edge" -> "Edge").
QJsonValue normalizedEnum(const QMetaProperty& property, const QJsonValue& value)
{
    if (!property.isEnumType() || !value.isString())
        return value;
    const QMetaEnum meta = property.enumerator();
    for (int i = 0; i < meta.keyCount(); ++i) {
        const QString key = QString::fromLatin1(meta.key(i));
        if (key.compare(value.toString(), Qt::CaseInsensitive) == 0)
            return key;
    }
    return value;
}

void logAction(const QString& message)
{
    EventLog::log(EventLog::Info, u"remote"_s, message);
}

QString compact(const QJsonObject& object)
{
    return QString::fromUtf8(QJsonDocument(object).toJson(QJsonDocument::Compact));
}

}  // namespace

RemoteControl::RemoteControl(Access access, QObject* parent)
    : QObject(parent)
    , m_access(access)
{
}

QString RemoteControl::accessName(Access access)
{
    switch (access) {
    case Observe: return u"observe"_s;
    case Control: return u"control"_s;
    case Off: break;
    }
    return u"off"_s;
}

RemoteControl::Access RemoteControl::parseAccess(const QString& text)
{
    const QString t = text.trimmed().toLower();
    if (t == u"control"_s || t == u"full"_s || t == u"rw"_s)
        return Control;
    if (t.isEmpty() || t == u"observe"_s || t == u"on"_s || t == u"1"_s || t == u"true"_s || t == u"read"_s
        || t == u"readonly"_s || t == u"ro"_s)
        return Observe;
    return Off;
}

bool RemoteControl::isRemoteWritable(const QMetaProperty& property)
{
    if (!property.isWritable() || !property.isStored() || property.isConstant() || isObjectPointer(property))
        return false;
    const int type = property.metaType().id();
    if (type == QMetaType::QUrl || type == QMetaType::QVariant || type == QMetaType::QVariantMap)
        return false;
    // Nothing that names, creates or appends to a file (logger folder, DMM log...).
    static const QRegularExpression files(u"file|folder|path|basename|record|append|directory"_s,
                                          QRegularExpression::CaseInsensitiveOption);
    return !files.match(QString::fromLatin1(property.name())).hasMatch();
}

RemoteControl::Inventory RemoteControl::inventory(InstrumentController* controller)
{
    Inventory inventory;
    const QMetaObject& base = InstrumentController::staticMetaObject;
    for (const QString& name : baseReadings()) {
        const int index = base.indexOfProperty(name.toLatin1().constData());
        if (index >= 0)
            inventory.readings.append({controller, base.property(index), name});
    }
    collect(controller, {}, 0, base.propertyCount(), inventory);
    return inventory;
}

QJsonObject RemoteControl::textResult(const QJsonValue& value, bool error)
{
    QString text;
    if (value.isString())
        text = value.toString();
    else if (value.isObject())
        text = QString::fromUtf8(QJsonDocument(value.toObject()).toJson(QJsonDocument::Indented));
    else if (value.isArray())
        text = QString::fromUtf8(QJsonDocument(value.toArray()).toJson(QJsonDocument::Indented));
    return QJsonObject{
        {u"content"_s, QJsonArray{QJsonObject{{u"type"_s, u"text"_s}, {u"text"_s, text}}}},
        {u"isError"_s, error},
    };
}

QJsonObject RemoteControl::listTools() const
{
    return QJsonObject{{u"tools"_s, publicTools(toolDefinitions(), m_access != Control)}};
}

void RemoteControl::call(const QString& name, const QJsonObject& arguments, const Reply& reply)
{
    QJsonObject definition;
    for (const QJsonValue& tool : toolDefinitions()) {
        if (tool.toObject().value(u"name"_s).toString() == name)
            definition = tool.toObject();
    }
    if (definition.isEmpty()) {
        reply(errorResult(u"Unknown tool '%1'."_s.arg(name)));
        return;
    }
    if (m_access == Off) {
        reply(errorResult(u"Remote control is off in mybench."_s));
        return;
    }
    if (definition.value(u"access"_s).toString() == u"control"_s && m_access != Control) {
        reply(errorResult(u"mybench allows observation only: %1 needs control access. Restart mybench with "
                          "--mcp=control to let the client change settings."_s.arg(name)));
        return;
    }

    if (name == u"get_status"_s)
        return reply(textResult(status()));
    if (name == u"read_measurements"_s)
        return readMeasurements(arguments, reply);
    if (name == u"get_trace"_s)
        return reply(trace(arguments));
    if (name == u"capture_screenshot"_s)
        return reply(screenshot(arguments));
    if (name == u"stop_all"_s) {
        InstrumentRegistry* registry = InstrumentRegistry::instance();
        registry->stopAll();
        for (const QString& id : registry->ids()) {
            if (InstrumentController* controller = registry->controller(id))
                controller->returnToSafeState();
        }
        logAction(u"Stopped every instrument"_s);
        return reply(textResult(u"Every instrument stopped; outputs back to their safe state."_s));
    }
    if (name == u"configure_instrument"_s)
        return reply(configure(arguments));
    if (name == u"run_instrument"_s)
        return runInstrument(arguments, reply);
    if (name == u"set_generator"_s)
        return setGenerator(arguments, reply);
    if (name == u"run_bode"_s)
        return runBode(arguments, reply);
    if (name == u"self_test"_s)
        return selfTest(reply);
    if (name == u"invoke_command"_s)
        return reply(invokeCommand(arguments));
    if (name == u"set_simulator"_s)
        return reply(setSimulator(arguments));

    QString error;
    InstrumentController* controller = controllerFor(arguments, &error);
    if (!controller)
        return reply(errorResult(error));
    if (name == u"describe_instrument"_s)
        return reply(textResult(describe(controller)));
    if (name == u"open_instrument"_s) {
        InstrumentRegistry::instance()->openInstrument(controller->instrumentId(), {},
                                                       arguments.value(u"beside"_s).toBool());
        return reply(textResult(u"%1 shown."_s.arg(controller->title())));
    }
    reply(errorResult(u"Tool '%1' is not implemented."_s.arg(name)));
}

InstrumentController* RemoteControl::controllerFor(const QJsonObject& arguments, QString* error) const
{
    const QString id = arguments.value(u"instrument"_s).toString().trimmed().toLower();
    InstrumentController* controller = id.isEmpty() ? nullptr : InstrumentRegistry::instance()->controller(id);
    if (!controller)
        *error = u"Unknown instrument '%1'. Instruments: %2."_s.arg(id, instrumentIds());
    return controller;
}

QJsonObject RemoteControl::status() const
{
    DeviceHub* hub = DeviceHub::instance();
    QJsonObject device{
        {u"id"_s, hub->currentId()},
        {u"name"_s, hub->name()},
        {u"connected"_s, hub->isConnected()},
        {u"simulated"_s, hub->isSimulated()},
        {u"backend"_s, hub->backend()},
        {u"serialNumber"_s, hub->serialNumber()},
    };
    if (hub->isSimulated()) {
        device.insert(u"simulator"_s, QJsonObject{
            {u"wiring"_s, u"AO 0 -> AI 0 direct; AO 0 -> RC low-pass -> AI 1"_s},
            {u"rcCutoffHz"_s, hub->simulatorRcCutoff()},
            {u"noiseRmsV"_s, hub->simulatorNoiseRms()},
        });
    }
    QJsonArray instruments;
    InstrumentRegistry* registry = InstrumentRegistry::instance();
    for (const QString& id : registry->ids()) {
        InstrumentController* controller = registry->controller(id);
        if (!controller)
            continue;
        QJsonObject entry{
            {u"id"_s, id},
            {u"title"_s, controller->title()},
            {u"state"_s, QString::fromLatin1(QMetaEnum::fromType<InstrumentController::State>().valueToKey(controller->state()))},
            {u"summary"_s, controller->summary()},
            {u"description"_s, registry->info(id).value(u"description"_s).toString()},
        };
        if (!controller->keyValue().isEmpty())
            entry.insert(u"keyValue"_s, controller->keyValue());
        if (controller->hasError())
            entry.insert(u"error"_s, controller->errorText());
        instruments.append(entry);
    }
    return QJsonObject{
        {u"app"_s, QStringLiteral(MYBENCH_DISPLAY_NAME)},
        {u"version"_s, QCoreApplication::applicationVersion()},
        {u"access"_s, accessName(m_access)},
        {u"device"_s, device},
        {u"instruments"_s, instruments},
    };
}

QJsonObject RemoteControl::describe(InstrumentController* controller) const
{
    const Inventory inv = inventory(controller);
    QJsonObject settings;
    for (const Setting& s : inv.settings) {
        QJsonObject entry{{u"value"_s, readValue(s.owner, s.property)}};
        const QJsonArray keys = enumKeys(s.property);
        if (!keys.isEmpty())
            entry.insert(u"options"_s, keys);
        else
            entry.insert(u"type"_s, QString::fromLatin1(s.property.metaType().name()));
        settings.insert(s.path, entry);
    }
    QJsonObject constants;
    for (const Setting& s : inv.constants)
        constants.insert(s.path, readValue(s.owner, s.property));
    QJsonArray traces;
    for (const Setting& s : inv.traces)
        traces.append(s.path);
    QJsonArray commands;
    for (const QVariant& command : controller->commands()) {
        const QVariantMap map = command.toMap();
        QJsonObject entry{{u"id"_s, map.value(u"id"_s).toString()}, {u"title"_s, map.value(u"title"_s).toString()}};
        if (!map.value(u"argumentLabel"_s).toString().isEmpty())
            entry.insert(u"argument"_s, map.value(u"argumentLabel"_s).toString());
        commands.append(entry);
    }
    return QJsonObject{
        {u"id"_s, controller->instrumentId()},
        {u"title"_s, controller->title()},
        {u"supportsSingle"_s, controller->supportsSingle()},
        {u"settings"_s, settings},
        {u"readings"_s, readings(controller)},
        {u"constants"_s, constants},
        {u"traces"_s, traces},
        {u"commands"_s, commands},
    };
}

QJsonObject RemoteControl::readings(InstrumentController* controller)
{
    QJsonObject result;
    for (const Setting& s : inventory(controller).readings) {
        const QJsonValue value = readValue(s.owner, s.property);
        if (value.isString() && value.toString().isEmpty())
            continue;
        result.insert(s.path, value);
    }
    return result;
}

void RemoteControl::writeSettings(InstrumentController* controller, const QJsonObject& settings, QJsonObject& applied,
                                  QJsonObject& refused)
{
    for (auto it = settings.constBegin(); it != settings.constEnd(); ++it) {
        QObject* owner = nullptr;
        QMetaProperty property;
        if (!resolve(controller, it.key(), &owner, &property)) {
            refused.insert(it.key(), u"no such setting (see describe_instrument)"_s);
            continue;
        }
        const bool isBase = owner == controller
                            && property.propertyIndex() < InstrumentController::staticMetaObject.propertyCount();
        if (isBase || !isRemoteWritable(property)) {
            refused.insert(it.key(), u"not remotely writable"_s);
            continue;
        }
        if (!json::writeProperty(owner, property, normalizedEnum(property, it.value()))) {
            const QJsonArray keys = enumKeys(property);
            refused.insert(it.key(), keys.isEmpty() ? u"invalid value"_s
                                                    : u"invalid value; one of: "_s + QVariant(keys.toVariantList()).toStringList().join(u", "_s));
            continue;
        }
        applied.insert(it.key(), readValue(owner, property));
    }
}

void RemoteControl::waitFor(std::function<bool()> done, int timeoutMs, std::function<void(bool)> then)
{
    if (done()) {
        then(true);
        return;
    }
    auto* timer = new QTimer(this);
    timer->setInterval(50);
    auto clock = std::make_shared<QElapsedTimer>();
    clock->start();
    connect(timer, &QTimer::timeout, this, [timer, clock, done, timeoutMs, then] {
        const bool finished = done();
        if (!finished && clock->elapsed() < timeoutMs)
            return;
        timer->stop();
        timer->deleteLater();
        then(finished);
    });
    timer->start();
}

void RemoteControl::readMeasurements(const QJsonObject& arguments, const Reply& reply)
{
    QString error;
    QPointer<InstrumentController> controller = controllerFor(arguments, &error);
    if (!controller)
        return reply(errorResult(error));
    auto answer = [controller, reply](bool fresh, const QString& note) {
        if (!controller)
            return reply(errorResult(u"The instrument went away."_s));
        QJsonObject result{{u"instrument"_s, controller->instrumentId()}, {u"readings"_s, readings(controller)}};
        if (!note.isEmpty())
            result.insert(u"note"_s, note);
        result.insert(u"fresh"_s, fresh);
        reply(textResult(result));
    };
    if (!arguments.value(u"fresh"_s).toBool())
        return answer(false, controller->isRunning() ? QString() : u"The instrument is not running: values are from its last run."_s);
    if (!controller->isRunning())
        return answer(false, u"The instrument is not running: values are from its last run. Start it with run_instrument."_s);
    const int timeout = int(std::clamp(arguments.value(u"timeout_s"_s).toDouble(5.0), 0.1, 120.0) * 1000);
    const int target = controller->acquisitionCount() + 2;
    waitFor([controller, target] { return !controller || controller->acquisitionCount() >= target || !controller->isRunning(); },
            timeout, [answer](bool ok) {
                answer(ok, ok ? QString() : u"No new acquisition within the timeout (waiting for a trigger?)."_s);
            });
}

QJsonObject RemoteControl::trace(const QJsonObject& arguments) const
{
    QString error;
    InstrumentController* controller = controllerFor(arguments, &error);
    if (!controller)
        return errorResult(error);
    const QString name = arguments.value(u"trace"_s).toString();
    plot::TraceBuffer* buffer = nullptr;
    QStringList names;
    for (const Setting& s : inventory(controller).traces) {
        names.append(s.path);
        if (s.path == name)
            buffer = qobject_cast<plot::TraceBuffer*>(s.property.read(s.owner).value<QObject*>());
    }
    if (!buffer)
        return errorResult(u"No trace '%1' in %2. Traces: %3."_s.arg(name, controller->instrumentId(), names.join(u", "_s)));

    const plot::TraceSnapshot snapshot = buffer->snapshot();
    if (!snapshot || snapshot->empty())
        return textResult(QJsonObject{{u"trace"_s, name}, {u"points"_s, 0}, {u"note"_s, u"The trace is empty: run the instrument first."_s}});
    const double xMin = arguments.value(u"x_min"_s).toDouble(-qInf());
    const double xMax = arguments.value(u"x_max"_s).toDouble(qInf());
    std::vector<size_t> inside;
    inside.reserve(snapshot->size());
    for (size_t i = 0; i < snapshot->size(); ++i) {
        const double x = snapshot->xAt(i);
        if (x >= xMin && x <= xMax)
            inside.push_back(i);
    }
    const size_t limit = size_t(std::clamp(arguments.value(u"max_points"_s).toInt(100), 2, 2000));
    const bool peaks = arguments.value(u"peaks"_s).toBool();
    QJsonArray x, y;
    auto add = [&](size_t i) {
        const double xv = snapshot->xAt(i), yv = snapshot->yAt(i);
        x.append(std::isfinite(xv) ? QJsonValue(xv) : QJsonValue());
        y.append(std::isfinite(yv) ? QJsonValue(yv) : QJsonValue());
    };
    if (inside.size() <= limit) {
        for (size_t i : inside)
            add(i);
    } else {
        for (size_t bucket = 0; bucket < limit; ++bucket) {
            const size_t from = bucket * inside.size() / limit, to = (bucket + 1) * inside.size() / limit;
            size_t pick = inside[(from + to) / 2];
            if (peaks) {
                for (size_t k = from; k < to; ++k) {
                    if (snapshot->yAt(inside[k]) > snapshot->yAt(pick))
                        pick = inside[k];
                }
            }
            add(pick);
        }
    }
    return textResult(QJsonObject{
        {u"trace"_s, name},
        {u"samples"_s, qint64(inside.size())},
        {u"points"_s, x.size()},
        {u"x"_s, x},
        {u"y"_s, y},
    });
}

QJsonObject RemoteControl::screenshot(const QJsonObject& arguments) const
{
    QQuickWindow* best = nullptr;
    for (QWindow* window : QGuiApplication::topLevelWindows()) {
        auto* quick = qobject_cast<QQuickWindow*>(window);
        if (!quick || !quick->isVisible())
            continue;
        if (!best || quick->width() * quick->height() > best->width() * best->height())
            best = quick;
    }
    if (!best)
        return errorResult(u"No mybench window to capture."_s);
    QImage image = best->grabWindow();
    if (image.isNull())
        return errorResult(u"The window could not be captured."_s);
    const int maxWidth = std::clamp(arguments.value(u"max_width"_s).toInt(1280), 200, 4096);
    if (image.width() > maxWidth)
        image = image.scaledToWidth(maxWidth, Qt::SmoothTransformation);
    QByteArray png;
    QBuffer buffer(&png);
    buffer.open(QIODevice::WriteOnly);
    image.save(&buffer, "PNG");
    return QJsonObject{
        {u"content"_s, QJsonArray{QJsonObject{
                           {u"type"_s, u"image"_s},
                           {u"data"_s, QString::fromLatin1(png.toBase64())},
                           {u"mimeType"_s, u"image/png"_s},
                       }}},
        {u"isError"_s, false},
    };
}

QJsonObject RemoteControl::configure(const QJsonObject& arguments)
{
    QString error;
    InstrumentController* controller = controllerFor(arguments, &error);
    if (!controller)
        return errorResult(error);
    const QJsonObject settings = arguments.value(u"settings"_s).toObject();
    if (settings.isEmpty())
        return errorResult(u"No settings given: pass {\"settings\": {path: value}} (paths from describe_instrument)."_s);
    QJsonObject applied, refused;
    writeSettings(controller, settings, applied, refused);
    if (!applied.isEmpty())
        logAction(u"%1: %2"_s.arg(controller->title(), compact(applied)));
    QJsonObject result{{u"instrument"_s, controller->instrumentId()}, {u"applied"_s, applied}};
    if (!refused.isEmpty())
        result.insert(u"refused"_s, refused);
    if (!controller->inputWarning().isEmpty())
        result.insert(u"warning"_s, controller->inputWarning());
    return textResult(result, applied.isEmpty());
}

void RemoteControl::runInstrument(const QJsonObject& arguments, const Reply& reply)
{
    QString error;
    QPointer<InstrumentController> controller = controllerFor(arguments, &error);
    if (!controller)
        return reply(errorResult(error));
    const QString action = arguments.value(u"action"_s).toString().toLower();
    auto state = [controller](const QString& note = {}) {
        QJsonObject result{
            {u"instrument"_s, controller->instrumentId()},
            {u"state"_s, QString::fromLatin1(QMetaEnum::fromType<InstrumentController::State>().valueToKey(controller->state()))},
        };
        if (!controller->summary().isEmpty())
            result.insert(u"summary"_s, controller->summary());
        if (controller->hasError())
            result.insert(u"error"_s, controller->errorText());
        if (!controller->inputWarning().isEmpty())
            result.insert(u"warning"_s, controller->inputWarning());
        if (!note.isEmpty())
            result.insert(u"note"_s, note);
        return result;
    };
    if (action == u"stop"_s) {
        controller->stop();
        logAction(u"%1: stop"_s.arg(controller->title()));
        return reply(textResult(state()));
    }
    if (action != u"run"_s && action != u"single"_s)
        return reply(errorResult(u"action must be run, single or stop."_s));
    if (!controller->canRun() && controller->isIdle() && !DeviceHub::instance()->isConnected())
        return reply(errorResult(u"No device is connected."_s));
    if (action == u"single"_s && !controller->supportsSingle())
        return reply(errorResult(u"%1 has no Single acquisition: use run."_s.arg(controller->title())));

    controller->clearInputWarning();
    if (action == u"run"_s) {
        controller->run();
        logAction(u"%1: run"_s.arg(controller->title()));
        // Report a refused start (invalid settings, busy outputs) instead of "Idle".
        waitFor([controller] { return !controller || controller->isRunning() || !controller->inputWarning().isEmpty() || controller->hasError(); },
                2000, [controller, reply, state](bool) {
                    if (!controller)
                        return reply(errorResult(u"The instrument went away."_s));
                    reply(textResult(state(), !controller->isRunning()));
                });
        return;
    }
    controller->runOnce();
    logAction(u"%1: single"_s.arg(controller->title()));
    if (!arguments.value(u"wait"_s).toBool(true))
        return reply(textResult(state()));
    const int timeout = int(std::clamp(arguments.value(u"timeout_s"_s).toDouble(30.0), 0.5, 600.0) * 1000);
    auto sawRun = std::make_shared<bool>(false);
    waitFor([controller, sawRun] {
                if (!controller)
                    return true;
                *sawRun = *sawRun || controller->isRunning();
                return (*sawRun && controller->isIdle()) || (!*sawRun && (!controller->inputWarning().isEmpty() || controller->hasError()));
            },
            timeout, [controller, reply, state](bool done) {
                if (!controller)
                    return reply(errorResult(u"The instrument went away."_s));
                QJsonObject result = state(done ? QString() : u"Still running after the timeout."_s);
                result.insert(u"readings"_s, readings(controller));
                reply(textResult(result, controller->hasError() || !controller->inputWarning().isEmpty()));
            });
}

void RemoteControl::setGenerator(const QJsonObject& arguments, const Reply& reply)
{
    QPointer<InstrumentController> gen = InstrumentRegistry::instance()->controller(u"gen"_s);
    if (!gen)
        return reply(errorResult(u"The function generator is not available."_s));
    const int channel = arguments.value(u"channel"_s).toInt(-1);
    if (channel != 0 && channel != 1)
        return reply(errorResult(u"channel must be 0 or 1."_s));
    const QString prefix = u"channel%1."_s.arg(channel);
    const QString waveform = arguments.value(u"waveform"_s).toString().toLower();

    QJsonObject settings;
    if (waveform == u"sine"_s || waveform == u"square"_s || waveform == u"triangle"_s) {
        settings.insert(prefix + u"mode"_s, u"Function"_s);
        settings.insert(prefix + u"shape"_s, waveform);
    } else if (waveform == u"dc"_s) {
        settings.insert(prefix + u"mode"_s, u"Dc"_s);
        if (arguments.contains(u"offset_v"_s))
            settings.insert(prefix + u"dcLevel"_s, arguments.value(u"offset_v"_s));
    } else if (!waveform.isEmpty() && waveform != u"off"_s) {
        return reply(errorResult(u"waveform must be sine, square, triangle, dc or off."_s));
    }
    if (arguments.contains(u"frequency_hz"_s))
        settings.insert(prefix + u"frequency"_s, arguments.value(u"frequency_hz"_s));
    if (arguments.contains(u"amplitude_vpp"_s))
        settings.insert(prefix + u"amplitude"_s, arguments.value(u"amplitude_vpp"_s));
    if (arguments.contains(u"offset_v"_s) && waveform != u"dc"_s)
        settings.insert(prefix + u"offset"_s, arguments.value(u"offset_v"_s));
    if (arguments.contains(u"duty_cycle_percent"_s))
        settings.insert(prefix + u"dutyCycle"_s, arguments.value(u"duty_cycle_percent"_s));

    // Mode first: the other settings of a channel apply to its mode.
    QJsonObject applied, refused;
    if (settings.contains(prefix + u"mode"_s))
        writeSettings(gen, QJsonObject{{prefix + u"mode"_s, settings.take(prefix + u"mode"_s)}}, applied, refused);
    writeSettings(gen, settings, applied, refused);

    const bool on = waveform != u"off"_s && arguments.value(u"output"_s).toBool(true);
    gen->clearInputWarning();
    QMetaObject::invokeMethod(gen, "setOutput", Q_ARG(int, channel), Q_ARG(bool, on));
    logAction(u"Function generator CH %1: %2, output %3"_s.arg(channel).arg(compact(applied), on ? u"on"_s : u"off"_s));

    auto report = [gen, channel, applied, refused, reply, on](bool) {
        if (!gen)
            return reply(errorResult(u"The function generator went away."_s));
        QObject* ch = gen->property(qPrintable(u"channel%1"_s.arg(channel))).value<QObject*>();
        QJsonObject result{{u"channel"_s, channel}, {u"applied"_s, applied}};
        if (!refused.isEmpty())
            result.insert(u"refused"_s, refused);
        if (ch) {
            for (const char* name : {"name", "summary", "readoutText", "outputOn", "generating", "errorText", "clippedSamples"}) {
                const QVariant value = ch->property(name);
                if (value.isValid() && !(value.typeId() == QMetaType::QString && value.toString().isEmpty()))
                    result.insert(QString::fromLatin1(name), QJsonValue::fromVariant(value));
            }
        }
        result.insert(u"generatorState"_s, QString::fromLatin1(QMetaEnum::fromType<InstrumentController::State>().valueToKey(gen->state())));
        if (gen->hasError())
            result.insert(u"error"_s, gen->errorText());
        if (!gen->inputWarning().isEmpty())
            result.insert(u"warning"_s, gen->inputWarning());
        const bool failed = gen->hasError() || !gen->inputWarning().isEmpty() || (on && ch && !ch->property("outputOn").toBool());
        reply(textResult(result, failed));
    };
    if (!on)
        return report(true);
    waitFor([gen] { return !gen || gen->state() == InstrumentController::Running || gen->hasError() || !gen->inputWarning().isEmpty(); },
            3000, report);
}

void RemoteControl::selfTest(const Reply& reply)
{
    DeviceHub* hub = DeviceHub::instance();
    if (!hub->isConnected())
        return reply(errorResult(u"No device is connected."_s));
    logAction(u"Device self-test"_s);
    hub->selfTest();   // stops every instrument first; read-only
    waitFor([hub] { return !hub->isSelfTesting(); }, 60000, [hub, reply](bool done) {
        if (!done)
            return reply(errorResult(u"The self-test did not finish within 60 s."_s));
        QJsonArray checks;
        bool passed = true;
        for (const QVariant& c : hub->selfTestChecks()) {
            const QVariantMap m = c.toMap();
            passed = passed && m.value(u"ok"_s).toBool();
            checks.append(QJsonObject{{u"name"_s, m.value(u"name"_s).toString()}, {u"ok"_s, m.value(u"ok"_s).toBool()},
                                      {u"detail"_s, m.value(u"detail"_s).toString()}});
        }
        reply(textResult(QJsonObject{{u"device"_s, hub->name()}, {u"passed"_s, passed && !checks.isEmpty()}, {u"checks"_s, checks}}));
    });
}

void RemoteControl::runBode(const QJsonObject& arguments, const Reply& reply)
{
    QPointer<InstrumentController> bode = InstrumentRegistry::instance()->controller(u"bode"_s);
    if (!bode)
        return reply(errorResult(u"The Bode analyzer is not available."_s));
    if (!DeviceHub::instance()->isConnected())
        return reply(errorResult(u"No device is connected."_s));

    QJsonObject settings, applied, refused;
    const std::pair<const char*, const char*> keys[] = {
        {"start_hz", "startFrequency"}, {"stop_hz", "stopFrequency"},
        {"steps_per_decade", "stepsPerDecade"}, {"amplitude_v", "peakAmplitude"}};
    for (const auto& [argument, property] : keys) {
        if (arguments.contains(QLatin1StringView(argument)))
            settings.insert(QString::fromLatin1(property), arguments.value(QLatin1StringView(argument)));
    }
    // Start before stop would be refused while start > the old stop; write them in an order that works.
    if (settings.contains(u"stopFrequency"_s) && settings.value(u"stopFrequency"_s).toDouble() > bode->property("stopFrequency").toDouble())
        writeSettings(bode, QJsonObject{{u"stopFrequency"_s, settings.take(u"stopFrequency"_s)}}, applied, refused);
    writeSettings(bode, settings, applied, refused);
    if (!bode->property("settingsValid").toBool())
        return reply(errorResult(u"The sweep settings are not valid (start must be below stop): %1"_s.arg(compact(applied))));

    if (arguments.value(u"show"_s).toBool(true))
        InstrumentRegistry::instance()->openInstrument(u"bode"_s);
    if (bode->isRunning())
        bode->stop();
    const double planned = bode->property("plannedSeconds").toDouble();
    const int rows = std::clamp(arguments.value(u"points"_s).toInt(25), 2, 400);
    const int timeout = int(std::clamp(arguments.value(u"timeout_s"_s).toDouble(planned * 1.5 + 30.0), 1.0, 900.0) * 1000);
    logAction(u"Bode analyzer: sweep %1"_s.arg(compact(applied)));

    // Wait for the stop, then sweep once and wait for the end.
    waitFor([bode] { return !bode || bode->isIdle(); }, 5000, [this, bode, rows, timeout, applied, refused, reply](bool) {
        if (!bode)
            return reply(errorResult(u"The Bode analyzer went away."_s));
        bode->clearInputWarning();
        bode->clearError();
        bode->runOnce();
        auto sawRun = std::make_shared<bool>(false);
        waitFor([bode, sawRun] {
                    if (!bode)
                        return true;
                    *sawRun = *sawRun || bode->isRunning();
                    return (*sawRun && bode->isIdle()) || (!*sawRun && (!bode->inputWarning().isEmpty() || bode->hasError()));
                },
                timeout, [bode, rows, applied, refused, reply](bool done) {
                    if (!bode)
                        return reply(errorResult(u"The Bode analyzer went away."_s));
                    QJsonObject result{{u"settings"_s, applied}};
                    if (!refused.isEmpty())
                        result.insert(u"refused"_s, refused);
                    for (const char* name : {"stimulusName", "stimulusInputName", "responseInputName", "pointCount",
                                             "totalPoints", "maxGainDb", "cutoffFrequencies", "unityGainFrequency",
                                             "phaseMargin", "phaseCrossoverFrequency", "gainMargin", "clippedCount",
                                             "mapping"}) {
                        const int index = bode->metaObject()->indexOfProperty(name);
                        if (index >= 0)
                            result.insert(QString::fromLatin1(name), readValue(bode, bode->metaObject()->property(index)));
                    }
                    // A table of the sweep: frequency, gain (unit of the Mapping setting), phase.
                    auto* gain = qobject_cast<plot::TraceBuffer*>(bode->property("gain").value<QObject*>());
                    auto* phase = qobject_cast<plot::TraceBuffer*>(bode->property("phase").value<QObject*>());
                    const plot::TraceSnapshot g = gain ? gain->snapshot() : nullptr;
                    const plot::TraceSnapshot p = phase ? phase->snapshot() : nullptr;
                    QJsonArray table;
                    if (g && !g->empty()) {
                        const size_t n = g->size(), count = std::min(n, size_t(rows));
                        for (size_t k = 0; k < count; ++k) {
                            const size_t i = count == 1 ? 0 : k * (n - 1) / (count - 1);
                            const double f = g->xAt(i), gv = g->yAt(i);
                            const double pv = p && i < p->size() ? p->yAt(i) : qQNaN();
                            auto num = [](double v) { return std::isfinite(v) ? QJsonValue(std::round(v * 1e4) / 1e4) : QJsonValue(); };
                            table.append(QJsonArray{num(f), num(gv), num(pv)});
                        }
                    }
                    result.insert(u"columns"_s, QJsonArray{u"frequency_hz"_s, u"gain"_s, u"phase_deg"_s});
                    result.insert(u"table"_s, table);
                    if (!done)
                        result.insert(u"note"_s, u"The sweep was still running at the timeout: partial result."_s);
                    if (bode->hasError())
                        result.insert(u"error"_s, bode->errorText());
                    if (!bode->inputWarning().isEmpty())
                        result.insert(u"warning"_s, bode->inputWarning());
                    reply(textResult(result, bode->hasError() || !bode->inputWarning().isEmpty() || table.isEmpty()));
                });
    });
}

QJsonObject RemoteControl::invokeCommand(const QJsonObject& arguments)
{
    QString error;
    InstrumentController* controller = controllerFor(arguments, &error);
    if (!controller)
        return errorResult(error);
    const QString id = arguments.value(u"command"_s).toString();
    QStringList known;
    for (const QVariant& command : controller->commands()) {
        const QVariantMap map = command.toMap();
        known.append(map.value(u"id"_s).toString());
        if (map.value(u"id"_s).toString() != id)
            continue;
        if (map.contains(u"enabled"_s) && !map.value(u"enabled"_s).toBool())
            return errorResult(u"Command '%1' is not available now."_s.arg(id));
        controller->invokeCommand(id, arguments.value(u"argument"_s).toVariant());
        logAction(u"%1: %2"_s.arg(controller->title(), map.value(u"title"_s).toString()));
        return textResult(u"%1: %2 done."_s.arg(controller->title(), map.value(u"title"_s).toString()));
    }
    return errorResult(u"No command '%1' in %2. Commands: %3."_s.arg(id, controller->instrumentId(), known.join(u", "_s)));
}

QJsonObject RemoteControl::setSimulator(const QJsonObject& arguments)
{
    DeviceHub* hub = DeviceHub::instance();
    if (!hub->isSimulated())
        return errorResult(u"set_simulator works with the simulated myDAQ only; a real device is in use."_s);
    QJsonObject applied;
    if (arguments.contains(u"rc_cutoff_hz"_s)) {
        const double hz = arguments.value(u"rc_cutoff_hz"_s).toDouble(1000.0);
        hub->setSimulatorRcCutoff(std::clamp(std::isfinite(hz) ? hz : 1000.0, 1.0, 50000.0));
        applied.insert(u"rcCutoffHz"_s, hub->simulatorRcCutoff());
    }
    if (arguments.contains(u"noise_rms_v"_s)) {
        const double volts = arguments.value(u"noise_rms_v"_s).toDouble(0.0005);
        hub->setSimulatorNoiseRms(std::clamp(std::isfinite(volts) ? volts : 0.0005, 0.0, 0.1));
        applied.insert(u"noiseRmsV"_s, hub->simulatorNoiseRms());
    }
    if (applied.isEmpty())
        return errorResult(u"Nothing to set: pass rc_cutoff_hz and/or noise_rms_v."_s);
    logAction(u"Simulator: %1"_s.arg(compact(applied)));
    return textResult(QJsonObject{{u"applied"_s, applied}});
}

}  // namespace mybench::mcp
