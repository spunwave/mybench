#pragma once

#include "mydaq/device_manager.h"

#include <memory>

namespace mydaq {

// Windows: the mybench-usb service (packaging/windows/usb-setup) lends mybench the plugged-in
// myDAQs while mybench runs, through Windows' own WinUSB, and gives them back to NI's driver when
// mybench quits or crashes. This provider holds the connection, asks for myDAQs that are on NI's
// driver or have none, and reports the ones it cannot have (NI software using them, no service).
// The USB provider opens them once they are on WinUSB.
std::unique_ptr<DeviceProvider> makeWindowsLeaseProvider();

namespace lease {
bool serviceRunning();   // the last call to the service worked
void giveBack();         // give the borrowed myDAQs back now, and do not take them again ...
void takeNow();          // ... until this: take them now, even from a running NI program
}  // namespace lease

}  // namespace mydaq
