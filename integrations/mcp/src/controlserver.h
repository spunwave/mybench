// ControlServer: the app side of the MCP bridge. Listens on a local socket (current user only)
// and serves the line protocol of mcpcommon.h with a RemoteControl. Off unless started with
// --mcp[=observe|control] or the setting remote/mcp.
#pragma once

#include "remotecontrol.h"

#include <QHash>
#include <QObject>
#include <QPointer>

QT_BEGIN_NAMESPACE
class QLocalServer;
class QLocalSocket;
QT_END_NAMESPACE

namespace mybench::mcp {

class ControlServer : public QObject
{
    Q_OBJECT

public:
    ControlServer(RemoteControl::Access access, QObject* parent = nullptr);
    ~ControlServer() override;

    // Listens on `name` (defaultSocketName() when empty). False if another MYBENCH already
    // serves that name or the socket cannot be created; errorString() says why.
    bool listen(const QString& name = {});
    QString serverName() const;
    QString errorString() const { return m_error; }
    RemoteControl* control() { return &m_control; }
    int clientCount() const { return int(m_buffers.size()); }

signals:
    void clientConnected(const QString& client);
    void clientDisconnected();

private:
    void accept();
    void readFrom(QLocalSocket* socket);
    void handle(QLocalSocket* socket, const QJsonObject& request);
    static void send(QLocalSocket* socket, const QJsonObject& message);

    RemoteControl m_control;
    QLocalServer* m_server = nullptr;
    QHash<QLocalSocket*, QByteArray> m_buffers;
    QString m_error;
};

// Called by the app shell once the instruments exist: starts the server when --mcp or the
// setting remote/mcp asks for it, and shows a toast when a client connects. Returns the server
// (owned by the application) or nullptr.
ControlServer* startFromSettings();

}  // namespace mybench::mcp
