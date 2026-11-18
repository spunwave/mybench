// MCP remote control against the simulated myDAQ: access levels, settings through the
// instruments' setters (clamping, refused file settings), generator -> scope / spectrum, a Bode
// sweep of the simulated RC filter, traces, screenshot; then the mybench-mcp bridge as a separate
// process speaking MCP on stdio, with and without a running app.
#include "controlserver.h"
#include "mcpcommon.h"
#include "remotecontrol.h"

#include <mybench/framework.h>

#include <QGuiApplication>
#include <QImage>
#include <QJsonDocument>
#include <QProcess>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSettings>
#include <QTemporaryDir>
#include <QTest>
#include <QUuid>

#include <cmath>

namespace mybench::instruments {
void registerScope(InstrumentRegistry& registry);
void registerGen(InstrumentRegistry& registry);
void registerBode(InstrumentRegistry& registry);
void registerDsa(InstrumentRegistry& registry);
void registerDmm(InstrumentRegistry& registry);
void registerLog(InstrumentRegistry& registry);
}  // namespace mybench::instruments

using namespace mybench;
using namespace mybench::mcp;
using namespace Qt::StringLiterals;

namespace {

// Calls a tool and waits for its reply (the event loop runs meanwhile).
QJsonObject callTool(RemoteControl& control, const QString& name, const QJsonObject& arguments = {}, int timeoutMs = 60000)
{
    QJsonObject result;
    bool done = false;
    control.call(name, arguments, [&](const QJsonObject& r) {
        result = r;
        done = true;
    });
    QElapsedTimer clock;
    clock.start();
    while (!done && clock.elapsed() < timeoutMs)
        QTest::qWait(20);
    if (!done)
        qWarning("tool %s timed out", qPrintable(name));
    return result;
}

QString text(const QJsonObject& result)
{
    return result.value(u"content"_s).toArray().at(0).toObject().value(u"text"_s).toString();
}

QJsonObject parsed(const QJsonObject& result)
{
    return QJsonDocument::fromJson(text(result).toUtf8()).object();
}

bool isError(const QJsonObject& result)
{
    return result.value(u"isError"_s).toBool();
}

QStringList toolNames(const QJsonObject& list)
{
    QStringList names;
    for (const QJsonValue& tool : list.value(u"tools"_s).toArray())
        names.append(tool.toObject().value(u"name"_s).toString());
    return names;
}

// One MCP session with the bridge process.
class BridgeProcess
{
public:
    explicit BridgeProcess(const QString& socketName)
    {
        m_process.setProcessChannelMode(QProcess::SeparateChannels);
        m_process.start(QStringLiteral(MYBENCH_MCP_BRIDGE), {u"--socket"_s, socketName});
    }
    ~BridgeProcess()
    {
        m_process.closeWriteChannel();
        if (!m_process.waitForFinished(3000))
            m_process.kill();
    }
    bool started() { return m_process.waitForStarted(5000); }

    QJsonObject request(const QString& method, const QJsonObject& params = {}, int timeoutMs = 30000)
    {
        const int id = ++m_id;
        send(QJsonObject{{u"jsonrpc"_s, u"2.0"_s}, {u"id"_s, id}, {u"method"_s, method}, {u"params"_s, params}});
        QElapsedTimer clock;
        clock.start();
        while (clock.elapsed() < timeoutMs) {
            // The event loop must run: the control server lives in this process.
            QTest::qWait(10);
            m_buffer += m_process.readAllStandardOutput();
            qsizetype end;
            while ((end = m_buffer.indexOf('\n')) >= 0) {
                const QJsonObject reply = QJsonDocument::fromJson(m_buffer.left(end)).object();
                m_buffer.remove(0, end + 1);
                if (reply.value(u"id"_s).toInt() == id)
                    return reply;
            }
        }
        qWarning("bridge: no reply to %s; stderr: %s", qPrintable(method), m_process.readAllStandardError().constData());
        return {};
    }
    void notify(const QString& method)
    {
        send(QJsonObject{{u"jsonrpc"_s, u"2.0"_s}, {u"method"_s, method}});
    }

private:
    void send(const QJsonObject& message)
    {
        m_process.write(QJsonDocument(message).toJson(QJsonDocument::Compact) + '\n');
    }

    QProcess m_process;
    QByteArray m_buffer;
    int m_id = 0;
};

QString uniqueSocket()
{
    const QString name = u"mybench-mcp-test-"_s + QUuid::createUuid().toString(QUuid::Id128).left(12);
#ifdef Q_OS_WIN
    return name;
#else
    return QDir::tempPath() + u'/' + name;
#endif
}

}  // namespace

class TestMcp : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase()
    {
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, m_dir.path());
        QCoreApplication::setOrganizationName(u"MYBENCH-test"_s);
        QCoreApplication::setApplicationName(u"tst_mcp"_s);
        InstrumentController::setRestoreSavedSettings(false);
        QVERIFY(DeviceHub::instance()->isSimulated());
        InstrumentRegistry* registry = InstrumentRegistry::instance();
        instruments::registerScope(*registry);
        instruments::registerGen(*registry);
        instruments::registerBode(*registry);
        instruments::registerDsa(*registry);
        instruments::registerDmm(*registry);
        instruments::registerLog(*registry);
        registry->createAll();
        QTRY_VERIFY(DeviceHub::instance()->isConnected());
    }

    void cleanup()
    {
        InstrumentRegistry::instance()->stopAll();
        QTRY_VERIFY_WITH_TIMEOUT(InstrumentRegistry::instance()->runningCount() == 0, 10000);
    }

    void cleanupTestCase() { InstrumentRegistry::instance()->shutdown(); }

    void toolDefinitionsAreValid()
    {
        const QJsonArray tools = toolDefinitions();
        QVERIFY(tools.size() >= 12);
        for (const QJsonValue& value : tools) {
            const QJsonObject tool = value.toObject();
            QVERIFY2(!tool.value(u"name"_s).toString().isEmpty(), "tool without a name");
            QVERIFY(!tool.value(u"description"_s).toString().isEmpty());
            QCOMPARE(tool.value(u"inputSchema"_s).toObject().value(u"type"_s).toString(), u"object"_s);
            const QString access = tool.value(u"access"_s).toString();
            QVERIFY2(access == u"observe"_s || access == u"control"_s, qPrintable(tool.value(u"name"_s).toString()));
        }
        for (const QJsonValue& value : publicTools(tools))
            QVERIFY(!value.toObject().contains(u"access"_s));
    }

    void socketNames()
    {
        const QStringList names = socketCandidates();
        QVERIFY(!names.isEmpty());
        QCOMPARE(defaultSocketName(), names.first());
#ifndef Q_OS_WIN
        for (const QString& name : names) {
            QVERIFY2(name.endsWith(u"/mybench-mcp.sock"_s), qPrintable(name));
            QVERIFY2(name.size() < 100, qPrintable(name));   // sockaddr_un limit
        }
#endif
        qputenv("MYBENCH_MCP_SOCKET", "custom-name");
        QCOMPARE(socketCandidates(), QStringList{u"custom-name"_s});
        qunsetenv("MYBENCH_MCP_SOCKET");
    }

    void accessLevels()
    {
        QCOMPARE(RemoteControl::parseAccess(u""_s), RemoteControl::Observe);
        QCOMPARE(RemoteControl::parseAccess(u"Control"_s), RemoteControl::Control);
        QCOMPARE(RemoteControl::parseAccess(u"off"_s), RemoteControl::Off);
        QCOMPARE(RemoteControl::parseAccess(u"nonsense"_s), RemoteControl::Off);

        RemoteControl observe(RemoteControl::Observe);
        const QStringList observeTools = toolNames(observe.listTools());
        QVERIFY(observeTools.contains(u"read_measurements"_s));
        QVERIFY(observeTools.contains(u"stop_all"_s));
        QVERIFY(!observeTools.contains(u"configure_instrument"_s));
        QVERIFY(!observeTools.contains(u"set_generator"_s));
        const QJsonObject refused = callTool(observe, u"set_generator"_s, {{u"channel"_s, 0}, {u"frequency_hz"_s, 500}});
        QVERIFY(isError(refused));
        QVERIFY(text(refused).contains(u"--mcp=control"_s));
        QVERIFY(!InstrumentRegistry::instance()->controller(u"gen"_s)->isRunning());

        RemoteControl control(RemoteControl::Control);
        QCOMPARE(toolNames(control.listTools()).size(), toolDefinitions().size());
        QVERIFY(isError(callTool(control, u"no_such_tool"_s)));
    }

    void status()
    {
        RemoteControl control(RemoteControl::Observe);
        const QJsonObject status = parsed(callTool(control, u"get_status"_s));
        QCOMPARE(status.value(u"access"_s).toString(), u"observe"_s);
        QVERIFY(status.value(u"device"_s).toObject().value(u"simulated"_s).toBool());
        QVERIFY(status.value(u"device"_s).toObject().contains(u"simulator"_s));
        QStringList ids;
        for (const QJsonValue& entry : status.value(u"instruments"_s).toArray())
            ids.append(entry.toObject().value(u"id"_s).toString());
        QVERIFY(ids.contains(u"scope"_s));
        QVERIFY(ids.contains(u"bode"_s));
    }

    void describe()
    {
        RemoteControl control(RemoteControl::Observe);
        const QJsonObject scope = parsed(callTool(control, u"describe_instrument"_s, {{u"instrument"_s, u"scope"_s}}));
        const QJsonObject settings = scope.value(u"settings"_s).toObject();
        QVERIFY(settings.contains(u"timePerDiv"_s));
        QVERIFY(settings.contains(u"channel0.voltsPerDiv"_s));
        QVERIFY(settings.value(u"triggerType"_s).toObject().value(u"options"_s).toArray().contains(u"Edge"_s));
        QVERIFY(scope.value(u"traces"_s).toArray().contains(u"ch0"_s));
        QVERIFY(scope.value(u"readings"_s).toObject().contains(u"state"_s));
        QVERIFY(scope.value(u"readings"_s).toObject().contains(u"channel0.frequency"_s));
        // File settings are never writable remotely.
        const QJsonObject log = parsed(callTool(control, u"describe_instrument"_s, {{u"instrument"_s, u"log"_s}}));
        QVERIFY(!log.value(u"settings"_s).toObject().contains(u"folder"_s));
        QVERIFY(!log.value(u"settings"_s).toObject().contains(u"baseName"_s));
        QVERIFY(isError(callTool(control, u"describe_instrument"_s, {{u"instrument"_s, u"nope"_s}})));
    }

    void configureClampsAndRefuses()
    {
        RemoteControl control(RemoteControl::Control);
        const QJsonObject result = parsed(callTool(control, u"configure_instrument"_s, {
            {u"instrument"_s, u"gen"_s},
            {u"settings"_s, QJsonObject{{u"channel0.frequency"_s, 1e9}, {u"channel0.amplitude"_s, 50},
                                        {u"channel0.shape"_s, u"square"_s}, {u"channel0.bogus"_s, 1}}},
        }));
        const QJsonObject applied = result.value(u"applied"_s).toObject();
        QCOMPARE(applied.value(u"channel0.frequency"_s).toDouble(), 20000.0);   // the generator's limit
        QCOMPARE(applied.value(u"channel0.amplitude"_s).toDouble(), 10.0);
        QCOMPARE(applied.value(u"channel0.shape"_s).toString(), u"Square"_s);
        QVERIFY(result.value(u"refused"_s).toObject().contains(u"channel0.bogus"_s));

        const QJsonObject files = parsed(callTool(control, u"configure_instrument"_s, {
            {u"instrument"_s, u"log"_s}, {u"settings"_s, QJsonObject{{u"folder"_s, u"/tmp"_s}}}}));
        QVERIFY(files.value(u"refused"_s).toObject().contains(u"folder"_s));
        const QJsonObject base = parsed(callTool(control, u"configure_instrument"_s, {
            {u"instrument"_s, u"scope"_s}, {u"settings"_s, QJsonObject{{u"state"_s, u"Running"_s}}}}));
        QVERIFY(base.value(u"refused"_s).toObject().contains(u"state"_s));
    }

    void generatorToScopeAndSpectrum()
    {
        RemoteControl control(RemoteControl::Control);
        const QJsonObject gen = callTool(control, u"set_generator"_s, {
            {u"channel"_s, 0}, {u"waveform"_s, u"square"_s}, {u"frequency_hz"_s, 1000}, {u"amplitude_vpp"_s, 2}, {u"offset_v"_s, 0}});
        QVERIFY2(!isError(gen), qPrintable(text(gen)));
        QVERIFY(parsed(gen).value(u"outputOn"_s).toBool());
        QVERIFY(InstrumentRegistry::instance()->controller(u"gen"_s)->isRunning());

        // AO 0 is wired to AI 0 in the simulator: the scope sees 1 kHz.
        QVERIFY(!isError(callTool(control, u"configure_instrument"_s, {
            {u"instrument"_s, u"scope"_s}, {u"settings"_s, QJsonObject{{u"timePerDiv"_s, 0.001}}}})));
        const QJsonObject run = callTool(control, u"run_instrument"_s, {{u"instrument"_s, u"scope"_s}, {u"action"_s, u"run"_s}});
        QVERIFY2(!isError(run), qPrintable(text(run)));
        const QJsonObject readings = parsed(callTool(control, u"read_measurements"_s, {
            {u"instrument"_s, u"scope"_s}, {u"fresh"_s, true}, {u"timeout_s"_s, 10}})).value(u"readings"_s).toObject();
        const double frequency = readings.value(u"channel0.frequency"_s).toDouble();
        QVERIFY2(std::abs(frequency - 1000.0) < 20.0, qPrintable(QString::number(frequency)));
        const double peakToPeak = readings.value(u"channel0.peakToPeak"_s).toDouble();
        QVERIFY2(std::abs(peakToPeak - 2.0) < 0.3, qPrintable(QString::number(peakToPeak)));

        const QJsonObject trace = parsed(callTool(control, u"get_trace"_s, {
            {u"instrument"_s, u"scope"_s}, {u"trace"_s, u"ch0"_s}, {u"max_points"_s, 50}}));
        QCOMPARE(trace.value(u"points"_s).toInt(), 50);
        QCOMPARE(trace.value(u"y"_s).toArray().size(), 50);

        // A square wave has odd harmonics: the spectrum analyzer finds them.
        QVERIFY(!isError(callTool(control, u"run_instrument"_s, {{u"instrument"_s, u"dsa"_s}, {u"action"_s, u"run"_s}})));
        const QJsonObject dsa = parsed(callTool(control, u"read_measurements"_s, {
            {u"instrument"_s, u"dsa"_s}, {u"fresh"_s, true}, {u"timeout_s"_s, 15}})).value(u"readings"_s).toObject();
        const double fundamental = dsa.value(u"fundamentalFrequency"_s).toDouble();
        QVERIFY2(std::abs(fundamental - 1000.0) < 30.0, qPrintable(QString::number(fundamental)));
        QVERIFY(dsa.value(u"harmonics"_s).toArray().size() >= 2);
        QVERIFY(dsa.value(u"thd"_s).toDouble() > 20.0);   // square wave: about 48 %

        const QJsonObject stop = callTool(control, u"stop_all"_s);
        QVERIFY(!isError(stop));
        QTRY_VERIFY(InstrumentRegistry::instance()->runningCount() == 0);
    }

    void bodeOfTheSimulatedRcFilter()
    {
        RemoteControl control(RemoteControl::Control);
        QVERIFY(!isError(callTool(control, u"set_simulator"_s, {{u"rc_cutoff_hz"_s, 1000}})));
        const QJsonObject result = callTool(control, u"run_bode"_s, {
            {u"start_hz"_s, 50}, {u"stop_hz"_s, 20000}, {u"steps_per_decade"_s, 10}, {u"points"_s, 10}, {u"show"_s, false}}, 120000);
        QVERIFY2(!isError(result), qPrintable(text(result)));
        const QJsonObject bode = parsed(result);
        const QJsonArray cutoffs = bode.value(u"cutoffFrequencies"_s).toArray();
        QVERIFY2(!cutoffs.isEmpty(), qPrintable(text(result)));
        QVERIFY2(std::abs(cutoffs.at(0).toDouble() - 1000.0) < 150.0, qPrintable(text(result)));
        QCOMPARE(bode.value(u"table"_s).toArray().size(), 10);
        const QJsonArray last = bode.value(u"table"_s).toArray().last().toArray();
        QVERIFY(last.at(1).toDouble() < -20.0);   // 20 kHz: about -26 dB
        QVERIFY(last.at(2).toDouble() < -70.0);   // phase towards -90°

        const QJsonObject gain = parsed(callTool(control, u"get_trace"_s, {
            {u"instrument"_s, u"bode"_s}, {u"trace"_s, u"gain"_s}, {u"max_points"_s, 500}}));
        QVERIFY(gain.value(u"points"_s).toInt() > 20);

        // Start above stop is refused, not run.
        QVERIFY(isError(callTool(control, u"run_bode"_s, {{u"start_hz"_s, 5000}, {u"stop_hz"_s, 100}, {u"show"_s, false}})));
    }

    void simulatorLimits()
    {
        RemoteControl control(RemoteControl::Control);
        const QJsonObject result = parsed(callTool(control, u"set_simulator"_s, {{u"rc_cutoff_hz"_s, 0}, {u"noise_rms_v"_s, 5}}));
        QCOMPARE(result.value(u"applied"_s).toObject().value(u"rcCutoffHz"_s).toDouble(), 1.0);
        QCOMPARE(result.value(u"applied"_s).toObject().value(u"noiseRmsV"_s).toDouble(), 0.1);
        callTool(control, u"set_simulator"_s, {{u"rc_cutoff_hz"_s, 1000}, {u"noise_rms_v"_s, 0.0005}});
    }

    void commands()
    {
        RemoteControl control(RemoteControl::Control);
        const QJsonObject result = callTool(control, u"invoke_command"_s, {{u"instrument"_s, u"gen"_s}, {u"command"_s, u"nope"_s}});
        QVERIFY(isError(result));
        QVERIFY(text(result).contains(u"Commands:"_s));
    }

    void screenshot()
    {
        RemoteControl control(RemoteControl::Observe);
        QVERIFY(isError(callTool(control, u"capture_screenshot"_s)));   // no window yet
        QQuickWindow window;
        window.setColor(Qt::red);
        window.resize(640, 400);
        window.show();
        QVERIFY(QTest::qWaitForWindowExposed(&window));
        const QJsonObject result = callTool(control, u"capture_screenshot"_s, {{u"max_width"_s, 320}});
        QVERIFY(!isError(result));
        const QJsonObject image = result.value(u"content"_s).toArray().at(0).toObject();
        QCOMPARE(image.value(u"type"_s).toString(), u"image"_s);
        QCOMPARE(image.value(u"mimeType"_s).toString(), u"image/png"_s);
        const QImage png = QImage::fromData(QByteArray::fromBase64(image.value(u"data"_s).toString().toLatin1()), "PNG");
        QCOMPARE(png.width(), 320);
        QCOMPARE(png.pixelColor(10, 10), QColor(Qt::red));
    }

    void controlServerRefusesASecondInstance()
    {
        const QString name = uniqueSocket();
        ControlServer first(RemoteControl::Observe);
        QVERIFY2(first.listen(name), qPrintable(first.errorString()));
        ControlServer second(RemoteControl::Observe);
        QVERIFY(!second.listen(name));
        QVERIFY(second.errorString().contains(u"another mybench"_s));
    }

    void bridgeWithoutApp()
    {
        BridgeProcess bridge(uniqueSocket());
        QVERIFY(bridge.started());
        const QJsonObject init = bridge.request(u"initialize"_s, {
            {u"protocolVersion"_s, u"2025-06-18"_s}, {u"capabilities"_s, QJsonObject{}},
            {u"clientInfo"_s, QJsonObject{{u"name"_s, u"tst_mcp"_s}, {u"version"_s, u"1"_s}}}});
        QCOMPARE(init.value(u"result"_s).toObject().value(u"protocolVersion"_s).toString(), u"2025-06-18"_s);
        QCOMPARE(init.value(u"result"_s).toObject().value(u"serverInfo"_s).toObject().value(u"name"_s).toString(), u"mybench"_s);
        bridge.notify(u"notifications/initialized"_s);
        const QJsonObject list = bridge.request(u"tools/list"_s);
        QCOMPARE(toolNames(list.value(u"result"_s).toObject()).size(), toolDefinitions().size());
        const QJsonObject call = bridge.request(u"tools/call"_s, {{u"name"_s, u"get_status"_s}, {u"arguments"_s, QJsonObject{}}});
        QVERIFY(isError(call.value(u"result"_s).toObject()));
        QVERIFY(text(call.value(u"result"_s).toObject()).contains(u"--mcp=control"_s));
        QCOMPARE(bridge.request(u"no/such"_s).value(u"error"_s).toObject().value(u"code"_s).toInt(), -32601);
    }

    void bridgeWithApp()
    {
        const QString name = uniqueSocket();
        ControlServer server(RemoteControl::Control);
        QVERIFY2(server.listen(name), qPrintable(server.errorString()));
        QString client;
        connect(&server, &ControlServer::clientConnected, this, [&client](const QString& c) { client = c; });

        BridgeProcess bridge(name);
        QVERIFY(bridge.started());
        bridge.request(u"initialize"_s, {{u"protocolVersion"_s, u"2025-03-26"_s},
                                         {u"clientInfo"_s, QJsonObject{{u"name"_s, u"demo-client"_s}}}});
        bridge.notify(u"notifications/initialized"_s);
        const QJsonObject list = bridge.request(u"tools/list"_s);
        QVERIFY(toolNames(list.value(u"result"_s).toObject()).contains(u"set_generator"_s));
        QTRY_COMPARE(client, u"demo-client"_s);

        const QJsonObject status = bridge.request(u"tools/call"_s, {{u"name"_s, u"get_status"_s}, {u"arguments"_s, QJsonObject{}}});
        QVERIFY(!isError(status.value(u"result"_s).toObject()));
        QCOMPARE(parsed(status.value(u"result"_s).toObject()).value(u"access"_s).toString(), u"control"_s);

        const QJsonObject configure = bridge.request(u"tools/call"_s, {
            {u"name"_s, u"configure_instrument"_s},
            {u"arguments"_s, QJsonObject{{u"instrument"_s, u"scope"_s}, {u"settings"_s, QJsonObject{{u"timePerDiv"_s, 0.0005}}}}}});
        QVERIFY(!isError(configure.value(u"result"_s).toObject()));
        QCOMPARE(InstrumentRegistry::instance()->controller(u"scope"_s)->property("timePerDiv").toDouble(), 0.0005);
        QCOMPARE(bridge.request(u"ping"_s).value(u"result"_s).toObject(), QJsonObject());
    }

    void bridgeWithObservingApp()
    {
        const QString name = uniqueSocket();
        ControlServer server(RemoteControl::Observe);
        QVERIFY(server.listen(name));
        BridgeProcess bridge(name);
        QVERIFY(bridge.started());
        bridge.request(u"initialize"_s, {{u"protocolVersion"_s, u"2025-06-18"_s}});
        const QStringList tools = toolNames(bridge.request(u"tools/list"_s).value(u"result"_s).toObject());
        QVERIFY(tools.contains(u"get_status"_s));
        QVERIFY(!tools.contains(u"configure_instrument"_s));
    }

private:
    QTemporaryDir m_dir;
};

QTEST_MAIN(TestMcp)
#include "tst_mcp.moc"
