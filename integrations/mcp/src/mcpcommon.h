// Shared by the in-app control server and the mybench-mcp bridge.
//
// The app listens on a local socket (Unix domain socket in the user's runtime folder, a named pipe
// on Windows), readable by the current user only. One JSON object per line in both directions:
//     -> {"id": 1, "method": "hello", "params": {"client": "example-client"}}
//     <- {"id": 1, "result": {"app": "mybench", "version": "0.1.0", "access": "control"}}
//     -> {"id": 2, "method": "tools/list"}
//     <- {"id": 2, "result": {"tools": [...]}}
//     -> {"id": 3, "method": "tools/call", "params": {"name": "get_status", "arguments": {}}}
//     <- {"id": 3, "result": {"content": [{"type": "text", "text": "..."}], "isError": false}}
// tools/list and tools/call results are MCP results, forwarded unchanged by the bridge.
#pragma once

#include <QJsonArray>
#include <QString>
#include <QStringList>

namespace mybench::mcp {

// Socket names, most likely first: $MYBENCH_MCP_SOCKET if set, else per-user locations (Linux:
// $XDG_RUNTIME_DIR, /run/user/<uid>, Qt's runtime folder; macOS: $TMPDIR; Windows: a pipe).
QStringList socketCandidates();
// Where the app listens: the first candidate.
QString defaultSocketName();

// Every tool of tools.json (MCP tool objects plus the "access" key: "observe" or "control").
QJsonArray toolDefinitions();

// `tools` without the "access" keys, as tools/list returns them; `observeOnly` keeps the
// observe tools only.
QJsonArray publicTools(const QJsonArray& tools, bool observeOnly = false);

}  // namespace mybench::mcp
