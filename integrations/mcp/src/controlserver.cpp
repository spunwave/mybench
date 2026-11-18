#include "controlserver.h"

#include "mcpcommon.h"

#include <mybench/appinfo.h>
#include <mybench/eventlog.h>
#include <mybench/notifications.h>

#include <QCoreApplication>
#include <QJsonDocument>
#include <QLocalServer>
#include <QLocalSocket>
#include <QSettings>

#include <cstdio>

using namespace Qt::StringLiterals;

namespace mybench::mcp {

namespace {
constexpr qsizetype kMaxLine = 1 << 20;   // a request larger than 1 MB closes the connection
}

ControlServer::ControlServer(RemoteControl::Access access, QObject* parent)
    : QObject(parent)
    , m_control(access, this)
{
}

ControlServer::~ControlServer()
{
    if (m_server)
        m_server->close();
}

bool ControlServer::listen(const QString& requested)
{
    const QString name = requested.isEmpty() ? defaultSocketName() : requested;
    // A live server on the name belongs to another MYBENCH: leave it alone. A dead one is a
    // socket file left by a crash: remove it.
    {
        QLocalSocket probe;
        probe.connectToServer(name);
        if (probe.waitForConnected(200)) {
            m_error = u"another mybench already serves %1"_s.arg(name);
            return false;
        }
    }
    QLocalServer::removeServer(name);
    m_server = new QLocalServer(this);
    m_server->setSocketOptions(QLocalServer::UserAccessOption);
    if (!m_server->listen(name)) {
        m_error = m_server->errorString();
        delete m_server;
        m_server = nullptr;
        return false;
    }
    connect(m_server, &QLocalServer::newConnection, this, &ControlServer::accept);
    return true;
}

QString ControlServer::serverName() const
{
    return m_server ? m_server->fullServerName() : QString();
}

void ControlServer::accept()
{
    while (QLocalSocket* socket = m_server->nextPendingConnection()) {
        m_buffers.insert(socket, {});
        connect(socket, &QLocalSocket::readyRead, this, [this, socket] { readFrom(socket); });
        connect(socket, &QLocalSocket::disconnected, this, [this, socket] {
            m_buffers.remove(socket);
            socket->deleteLater();
            emit clientDisconnected();
        });
    }
}

void ControlServer::readFrom(QLocalSocket* socket)
{
    QByteArray& buffer = m_buffers[socket];
    buffer += socket->readAll();
    qsizetype end;
    while ((end = buffer.indexOf('\n')) >= 0) {
        const QByteArray line = buffer.left(end).trimmed();
        buffer.remove(0, end + 1);
        if (line.isEmpty())
            continue;
        QJsonParseError error{};
        const QJsonDocument document = QJsonDocument::fromJson(line, &error);
        if (!document.isObject()) {
            send(socket, QJsonObject{{u"id"_s, QJsonValue()},
                                     {u"error"_s, QJsonObject{{u"code"_s, -32700}, {u"message"_s, u"Parse error"_s}}}});
            continue;
        }
        handle(socket, document.object());
    }
    if (buffer.size() > kMaxLine)
        socket->disconnectFromServer();
}

void ControlServer::handle(QLocalSocket* socket, const QJsonObject& request)
{
    const QJsonValue id = request.value(u"id"_s);
    const QString method = request.value(u"method"_s).toString();
    const QJsonObject params = request.value(u"params"_s).toObject();
    QPointer<QLocalSocket> target = socket;
    auto answer = [target, id](const QJsonObject& result) {
        if (target)
            send(target, QJsonObject{{u"id"_s, id}, {u"result"_s, result}});
    };
    if (method == u"hello"_s) {
        emit clientConnected(params.value(u"client"_s).toString());
        return answer(QJsonObject{
            {u"app"_s, QStringLiteral(MYBENCH_DISPLAY_NAME)},
            {u"version"_s, QCoreApplication::applicationVersion()},
            {u"access"_s, RemoteControl::accessName(m_control.access())},
        });
    }
    if (method == u"tools/list"_s)
        return answer(m_control.listTools());
    if (method == u"tools/call"_s) {
        m_control.call(params.value(u"name"_s).toString(), params.value(u"arguments"_s).toObject(), answer);
        return;
    }
    send(socket, QJsonObject{{u"id"_s, id},
                             {u"error"_s, QJsonObject{{u"code"_s, -32601}, {u"message"_s, u"Unknown method "_s + method}}}});
}

void ControlServer::send(QLocalSocket* socket, const QJsonObject& message)
{
    socket->write(QJsonDocument(message).toJson(QJsonDocument::Compact) + '\n');
    socket->flush();
}

ControlServer* startFromSettings()
{
    AppInfo* info = AppInfo::instance();
    // --mcp (observe), --mcp=observe|control|off; else the setting remote/mcp (default off).
    QString requested;
    if (!info->value(u"mcp"_s).isEmpty())
        requested = info->value(u"mcp"_s);
    else if (info->flag(u"mcp"_s))
        requested = u"observe"_s;
    else
        requested = QSettings().value(u"remote/mcp"_s, u"off"_s).toString();
    const RemoteControl::Access access = RemoteControl::parseAccess(requested);
    if (access == RemoteControl::Off)
        return nullptr;

    auto* server = new ControlServer(access, qApp);
    if (!server->listen(info->value(u"mcp-socket"_s))) {
        const QString message = u"Remote control (MCP) is not available: %1."_s.arg(server->errorString());
        std::fprintf(stderr, "mybench: %s\n", qPrintable(message));
        EventLog::log(EventLog::Warning, u"remote"_s, message);
        delete server;
        return nullptr;
    }
    const QString mode = access == RemoteControl::Control ? u"can change settings"_s : u"read only"_s;
    std::fprintf(stderr, "mybench: remote control (MCP, %s) on %s\n", qPrintable(RemoteControl::accessName(access)),
                 qPrintable(server->serverName()));
    EventLog::log(EventLog::Info, u"remote"_s, u"Remote control (MCP) on, %1"_s.arg(mode), server->serverName());
    QObject::connect(server, &ControlServer::clientConnected, server, [mode](const QString& client) {
        const QString who = client.isEmpty() ? u"An MCP client"_s : client;
        Notifications::instance()->show(Notifications::Info, u"Remote control connected"_s, u"%1 · %2"_s.arg(who, mode));
        EventLog::log(EventLog::Info, u"remote"_s, u"%1 connected"_s.arg(who));
    });
    return server;
}

}  // namespace mybench::mcp
