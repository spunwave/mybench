#include "mcpcommon.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>

#ifndef Q_OS_WIN
#include <unistd.h>
#endif

using namespace Qt::StringLiterals;

static void initMcpResources()
{
    Q_INIT_RESOURCE(mybench_mcp_tools);
}

namespace mybench::mcp {

QStringList socketCandidates()
{
    const QString overridden = qEnvironmentVariable("MYBENCH_MCP_SOCKET");
    if (!overridden.isEmpty())
        return {overridden};
#ifdef Q_OS_WIN
    return {u"mybench-mcp-"_s + qEnvironmentVariable("USERNAME")};
#else
    // Full paths in per-user folders: QLocalServer would otherwise use /tmp, shared by every user
    // of the machine. The app and the MCP client may not share an environment (a terminal without
    // XDG_RUNTIME_DIR, a desktop session with it), so every likely folder is listed and the
    // bridge tries them in order. Socket paths are limited to ~100 characters.
    QStringList folders;
#ifdef Q_OS_MACOS
    folders << QDir::tempPath();   // $TMPDIR: per user, short
#else
    folders << qEnvironmentVariable("XDG_RUNTIME_DIR");
    const QFileInfo run(u"/run/user/%1"_s.arg(::getuid()));
    if (run.isDir() && run.ownerId() == ::getuid())
        folders << run.absoluteFilePath();
    folders << QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
#endif
    QStringList names;
    for (const QString& folder : std::as_const(folders)) {
        const QString name = folder + u"/mybench-mcp.sock"_s;
        if (!folder.isEmpty() && !names.contains(name))
            names << name;
    }
    if (names.isEmpty())
        names << QDir::tempPath() + u"/mybench-mcp.sock"_s;
    return names;
#endif
}

QString defaultSocketName()
{
    return socketCandidates().constFirst();
}

QJsonArray toolDefinitions()
{
    static const QJsonArray tools = [] {
        initMcpResources();
        QFile file(u":/mybench/mcp/tools.json"_s);
        if (!file.open(QIODevice::ReadOnly))
            qFatal("mybench-mcp: tools.json is missing from the resources");
        return QJsonDocument::fromJson(file.readAll()).array();
    }();
    return tools;
}

QJsonArray publicTools(const QJsonArray& tools, bool observeOnly)
{
    QJsonArray result;
    for (const QJsonValue& value : tools) {
        QJsonObject tool = value.toObject();
        if (observeOnly && tool.value(u"access"_s).toString() != u"observe"_s)
            continue;
        tool.remove(u"access"_s);
        result.append(tool);
    }
    return result;
}

}  // namespace mybench::mcp
