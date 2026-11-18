// mybench-bode: the Bode Analyzer panel alone in a minimal shell (device selector, toasts, help).
#include "bodecontroller.h"

#include <mybench/shell.h>

int main(int argc, char* argv[])
{
    return mybench::runShell(argc, argv, {
        .instrumentId = QStringLiteral("bode"),
        .registerInstruments = [](mybench::InstrumentRegistry& registry) {
            mybench::instruments::registerBode(registry);
        },
    });
}
