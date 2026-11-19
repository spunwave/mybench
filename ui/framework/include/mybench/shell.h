// Bootstrap shared by every MYBENCH executable (the app, the dev executables, the gallery).
//
//     int main(int argc, char* argv[])
//     {
//         return mybench::runShell(argc, argv, {
//             .instrumentId = QStringLiteral("scope"),
//             .registerInstruments = [](mybench::InstrumentRegistry& r) {
//                 mybench::instruments::registerScope(r);
//             },
//         });
//     }
//
// runShell() sets the application identity and style, points QSettings at a temporary empty store
// for --fresh (implied by --screenshot unless --keep-settings), registers the instruments,
// creates their controllers, passes the launch options to AppInfo, loads the root QML through
// mybench::runQmlApp() and shuts the controllers down at exit.
#pragma once

#include <QSize>
#include <QString>

#include <functional>

namespace mybench {

class InstrumentRegistry;

struct ShellConfig {
    // Root QML type (a Window/ApplicationWindow or an Item).
    QString module = QStringLiteral("MyBench.Controls");
    QString type = QStringLiteral("DevShell");
    // Instrument of a dev executable (the DevShell's `instrumentId`; --instrument overrides).
    QString instrumentId;
    // Registers the instruments built into the executable (called before QML loads).
    std::function<void(InstrumentRegistry&)> registerInstruments;
    QSize defaultSize{1280, 800};
    // Called once the instruments exist and the session is loaded, before the root QML loads
    // (the app starts its MCP control server here).
    std::function<void()> started;
    // Extra lines for --help (options handled by `started`).
    const char* extraHelp = nullptr;
};

int runShell(int argc, char* argv[], const ShellConfig& config);

// The controls style a normal start uses: "mybench" when the QSettings key `appearance/controls`
// is "mybench", else "native".
QString storedControlsStyle();

}  // namespace mybench
