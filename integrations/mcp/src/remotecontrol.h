// RemoteControl: the tools of tools.json implemented on the running app (InstrumentRegistry,
// DeviceHub), for an MCP client connected through ControlServer and mybench-mcp.
//
// Everything runs on the UI thread. Settings are written through the instruments' own property
// setters, exactly as the knobs do, so the limits the app enforces (output range, frequency
// limits, resource arbitration) apply unchanged. Settings naming files or folders are never
// writable remotely. In Observe access only the reading tools (and stop_all) run.
#pragma once

#include <QJsonArray>
#include <QJsonObject>
#include <QMetaProperty>
#include <QObject>

#include <functional>

namespace mybench {
class InstrumentController;
}

namespace mybench::mcp {

class RemoteControl : public QObject
{
    Q_OBJECT

public:
    enum Access { Off, Observe, Control };
    Q_ENUM(Access)

    using Reply = std::function<void(const QJsonObject& result)>;   // an MCP CallToolResult

    explicit RemoteControl(Access access, QObject* parent = nullptr);

    Access access() const { return m_access; }
    static QString accessName(Access access);
    // "observe" / "control" / "off" (also "on", "1", "true", "" = observe); Off if unknown.
    static Access parseAccess(const QString& text);

    // tools/list result for this access.
    QJsonObject listTools() const;
    // tools/call: `reply` is called exactly once, at once or later (waiting tools).
    void call(const QString& name, const QJsonObject& arguments, const Reply& reply);

    // --- Helpers, public for the tests --------------------------------------------------------
    struct Setting {
        QObject* owner = nullptr;
        QMetaProperty property;
        QString path;   // "channel0.voltsPerDiv"
    };
    // Settings an MCP client may write, readings, and traces of an instrument.
    struct Inventory {
        QList<Setting> settings;
        QList<Setting> readings;
        QList<Setting> constants;
        QList<Setting> traces;
    };
    static Inventory inventory(InstrumentController* controller);
    static bool isRemoteWritable(const QMetaProperty& property);

    static QJsonObject textResult(const QJsonValue& value, bool error = false);
    static QJsonObject errorResult(const QString& message) { return textResult(message, true); }

private:
    InstrumentController* controllerFor(const QJsonObject& arguments, QString* error) const;
    QJsonObject status() const;
    QJsonObject describe(InstrumentController* controller) const;
    static QJsonObject readings(InstrumentController* controller);
    // Writes { path: value }; fills `applied` (values read back) and `refused` ({ path: reason }).
    static void writeSettings(InstrumentController* controller, const QJsonObject& settings, QJsonObject& applied,
                              QJsonObject& refused);
    // Polls `done` every 50 ms until it returns true or `timeoutMs` elapses, then `then(done())`.
    void waitFor(std::function<bool()> done, int timeoutMs, std::function<void(bool)> then);

    void readMeasurements(const QJsonObject& arguments, const Reply& reply);
    QJsonObject trace(const QJsonObject& arguments) const;
    QJsonObject screenshot(const QJsonObject& arguments) const;
    QJsonObject configure(const QJsonObject& arguments);
    void runInstrument(const QJsonObject& arguments, const Reply& reply);
    void setGenerator(const QJsonObject& arguments, const Reply& reply);
    void runBode(const QJsonObject& arguments, const Reply& reply);
    QJsonObject invokeCommand(const QJsonObject& arguments);
    QJsonObject setSimulator(const QJsonObject& arguments);

    Access m_access;
};

}  // namespace mybench::mcp
