// mybench: the MYBENCH application shell (app/Main.qml) with every built instrument.
#include <mybench/instrumentregistry.h>
#include <mybench/shell.h>

#ifdef MYBENCH_WITH_MCP
#include <controlserver.h>   // integrations/mcp
#endif

void registerBuiltInstruments(mybench::InstrumentRegistry& registry);   // generated instruments.cpp

int main(int argc, char* argv[])
{
    mybench::ShellConfig config{
        .module = QStringLiteral("MyBench.App"),
        .type = QStringLiteral("Main"),
        .registerInstruments = registerBuiltInstruments,
        .defaultSize = {1440, 900},
    };
#ifdef MYBENCH_WITH_MCP
    config.started = [] { mybench::mcp::startFromSettings(); };
    config.extraHelp = "  --mcp[=observe|control] remote control for MCP clients through mybench-mcp:\n"
                       "                           observe (the default) reads only, control may change settings\n"
                       "                           and run instruments; --mcp=off overrides the setting remote/mcp\n"
                       "  --mcp-socket=<name>      socket of the remote control (default: per user)\n";
#endif
    return mybench::runShell(argc, argv, config);
}
