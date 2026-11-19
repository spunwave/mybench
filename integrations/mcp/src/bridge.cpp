// mybench-mcp: MCP server (stdio) for mybench. An MCP client starts it; it forwards the tool calls
// to a running mybench started with --mcp. It holds no device itself and needs only QtCore and
// QtNetwork.
//
// stdin/stdout: JSON-RPC 2.0, one message per line (MCP stdio transport). Logs go to stderr.
#include "mcpcommon.h"

#include <QCoreApplication>
#include <QHash>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalSocket>
#include <QTimer>

#include <cstdio>
#include <iostream>
#include <string>
#include <thread>

using namespace Qt::StringLiterals;
using namespace mybench::mcp;

namespace {

const QStringList kProtocolVersions{u"2025-06-18"_s, u"2025-03-26"_s, u"2024-11-05"_s};

const char* const kInstructions =
    "mybench is a bench instrument suite for the NI myDAQ (oscilloscope, function generator, Bode "
    "analyzer, spectrum analyzer, multimeter, digital I/O, counter, logger). These tools drive the "
    "running app live: what you change is visible on the presenter's screen. Call get_status first "
    "(device, access level, instruments), describe_instrument before configure_instrument, and "
    "read_measurements with fresh=true after a change. With the simulated myDAQ, AO 0 is wired to "
    "AI 0 directly and to AI 1 through an RC low-pass (set_simulator changes its cutoff). Values "
    "are clamped to the device limits by the app; the replies give the values actually applied.";

class Bridge : public QObject
{
public:
    explicit Bridge(QStringList socketNames)
        : m_socketNames(std::move(socketNames))
    {
        connect(&m_socket, &QLocalSocket::readyRead, this, &Bridge::readApp);
        connect(&m_socket, &QLocalSocket::disconnected, this, [this] {
            failPending(u"mybench closed the connection (the app quit?)."_s);
        });
    }

    ~Bridge() override
    {
        // The socket outlives m_pending during destruction: no failPending() from its signals.
        disconnect(&m_socket, nullptr, this, nullptr);
    }

    void handleLine(const QByteArray& line)
    {
        QJsonParseError error{};
        const QJsonDocument document = QJsonDocument::fromJson(line, &error);
        if (!document.isObject()) {
            write(QJsonObject{{u"jsonrpc"_s, u"2.0"_s}, {u"id"_s, QJsonValue()},
                              {u"error"_s, QJsonObject{{u"code"_s, -32700}, {u"message"_s, u"Parse error"_s}}}});
            return;
        }
        const QJsonObject message = document.object();
        const QString method = message.value(u"method"_s).toString();
        const QJsonValue id = message.value(u"id"_s);
        const QJsonObject params = message.value(u"params"_s).toObject();
        if (!message.contains(u"id"_s))
            return;   // notifications (initialized, cancelled): nothing to answer

        if (method == u"initialize"_s) {
            m_client = params.value(u"clientInfo"_s).toObject().value(u"name"_s).toString();
            const QString requested = params.value(u"protocolVersion"_s).toString();
            respond(id, QJsonObject{
                {u"protocolVersion"_s, kProtocolVersions.contains(requested) ? requested : kProtocolVersions.first()},
                {u"capabilities"_s, QJsonObject{{u"tools"_s, QJsonObject{{u"listChanged"_s, false}}}}},
                {u"serverInfo"_s, QJsonObject{{u"name"_s, u"mybench"_s}, {u"title"_s, u"mybench"_s},
                                              {u"version"_s, QStringLiteral(MYBENCH_VERSION)}}},
                {u"instructions"_s, QString::fromUtf8(kInstructions)},
            });
            return;
        }
        if (method == u"ping"_s)
            return respond(id, QJsonObject{});
        if (method == u"tools/list"_s) {
            // The app's list matches its access level; without the app, every tool (a call then
            // explains how to start mybench).
            if (ensureConnected()) {
                forward(id, u"tools/list"_s, {}, [this, id](const QJsonObject& result) { respond(id, result); });
                return;
            }
            return respond(id, QJsonObject{{u"tools"_s, publicTools(toolDefinitions())}});
        }
        if (method == u"tools/call"_s) {
            if (!ensureConnected()) {
                return respond(id, QJsonObject{
                    {u"content"_s, QJsonArray{QJsonObject{{u"type"_s, u"text"_s}, {u"text"_s,
                        u"mybench is not running with remote control on. Start it with `mybench --mcp=control` "
                        "(add --simulated for the simulated myDAQ), then call the tool again."_s}}}},
                    {u"isError"_s, true}});
            }
            forward(id, u"tools/call"_s, params, [this, id](const QJsonObject& result) { respond(id, result); });
            return;
        }
        write(QJsonObject{{u"jsonrpc"_s, u"2.0"_s}, {u"id"_s, id},
                          {u"error"_s, QJsonObject{{u"code"_s, -32601}, {u"message"_s, u"Method not found: "_s + method}}}});
    }

private:
    using Handler = std::function<void(const QJsonObject&)>;

    bool ensureConnected()
    {
        if (m_socket.state() == QLocalSocket::ConnectedState)
            return true;
        bool connected = false;
        for (const QString& name : std::as_const(m_socketNames)) {
            m_socket.abort();
            m_socket.connectToServer(name);
            if ((connected = m_socket.waitForConnected(500)))
                break;
        }
        if (!connected)
            return false;
        forward(QJsonValue(), u"hello"_s, QJsonObject{{u"client"_s, m_client}}, [](const QJsonObject& result) {
            std::fprintf(stderr, "mybench-mcp: connected to %s %s (%s)\n",
                         qPrintable(result.value(u"app"_s).toString()), qPrintable(result.value(u"version"_s).toString()),
                         qPrintable(result.value(u"access"_s).toString()));
        });
        return true;
    }

    void forward(const QJsonValue&, const QString& method, const QJsonObject& params, Handler handler)
    {
        const int id = ++m_nextId;
        m_pending.insert(id, std::move(handler));
        const QJsonObject request{{u"id"_s, id}, {u"method"_s, method}, {u"params"_s, params}};
        m_socket.write(QJsonDocument(request).toJson(QJsonDocument::Compact) + '\n');
        m_socket.flush();
    }

    void readApp()
    {
        m_buffer += m_socket.readAll();
        qsizetype end;
        while ((end = m_buffer.indexOf('\n')) >= 0) {
            const QByteArray line = m_buffer.left(end);
            m_buffer.remove(0, end + 1);
            const QJsonObject reply = QJsonDocument::fromJson(line).object();
            const int id = reply.value(u"id"_s).toInt();
            const Handler handler = m_pending.take(id);
            if (!handler)
                continue;
            if (reply.contains(u"error"_s)) {
                handler(QJsonObject{
                    {u"content"_s, QJsonArray{QJsonObject{{u"type"_s, u"text"_s},
                                                          {u"text"_s, reply.value(u"error"_s).toObject().value(u"message"_s).toString()}}}},
                    {u"isError"_s, true}});
            } else {
                handler(reply.value(u"result"_s).toObject());
            }
        }
    }

    void failPending(const QString& message)
    {
        const auto pending = std::exchange(m_pending, {});
        for (const Handler& handler : pending) {
            handler(QJsonObject{{u"content"_s, QJsonArray{QJsonObject{{u"type"_s, u"text"_s}, {u"text"_s, message}}}},
                                {u"isError"_s, true}});
        }
        m_buffer.clear();
    }

    void respond(const QJsonValue& id, const QJsonObject& result)
    {
        write(QJsonObject{{u"jsonrpc"_s, u"2.0"_s}, {u"id"_s, id}, {u"result"_s, result}});
    }

    static void write(const QJsonObject& message)
    {
        const QByteArray bytes = QJsonDocument(message).toJson(QJsonDocument::Compact) + '\n';
        std::fwrite(bytes.constData(), 1, size_t(bytes.size()), stdout);
        std::fflush(stdout);
    }

    QStringList m_socketNames;
    QString m_client;
    QLocalSocket m_socket;
    QByteArray m_buffer;
    QHash<int, Handler> m_pending;
    int m_nextId = 0;
};

}  // namespace

int main(int argc, char* argv[])
{
    QCoreApplication app(argc, argv);
    QCoreApplication::setApplicationName(u"mybench-mcp"_s);
    QStringList socketNames = socketCandidates();
    const QStringList arguments = app.arguments();
    for (qsizetype i = 1; i < arguments.size(); ++i) {
        const QString& argument = arguments[i];
        if (argument == u"--version"_s) {
            std::printf("mybench-mcp %s\n", MYBENCH_VERSION);
            return 0;
        }
        if (argument == u"--help"_s || argument == u"-h"_s) {
            std::printf("mybench-mcp: MCP server (stdio) controlling a running mybench.\n"
                        "Start mybench with --mcp=control (or --mcp for read-only), then let the MCP client run\n"
                        "this program. Options:\n"
                        "  --socket <name>   the app's socket (default: %s, or $MYBENCH_MCP_SOCKET)\n"
                        "  --list-tools      print the tool definitions and exit\n",
                        qPrintable(socketCandidates().join(u", then "_s)));
            return 0;
        }
        if (argument == u"--list-tools"_s) {
            std::printf("%s", QJsonDocument(publicTools(toolDefinitions())).toJson().constData());
            return 0;
        }
        if (argument == u"--socket"_s && i + 1 < arguments.size())
            socketNames = {arguments[++i]};
        else if (argument.startsWith(u"--socket="_s))
            socketNames = {argument.mid(9)};
    }

    Bridge bridge(socketNames);
    // stdin is read by a thread (portable; QSocketNotifier does not work on Windows consoles).
    std::thread reader([&bridge] {
        std::string line;
        while (std::getline(std::cin, line)) {
            const QByteArray bytes = QByteArray::fromStdString(line).trimmed();
            if (bytes.isEmpty())
                continue;
            QMetaObject::invokeMethod(&bridge, [&bridge, bytes] { bridge.handleLine(bytes); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(qApp, [] { QCoreApplication::quit(); }, Qt::QueuedConnection);
    });
    reader.detach();
    return app.exec();
}
