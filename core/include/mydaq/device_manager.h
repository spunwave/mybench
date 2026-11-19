// Device discovery: one list of devices from all backends (simulator, native USB, ...).
#pragma once

#include "mydaq/device.h"

#include <QObject>
#include <QList>

#include <memory>

namespace mydaq {

// A backend that can find devices. scan() is called on rescans and must be cheap for devices that
// are already open (return the same DevicePtr for a device that is still present).
// Why an attached myDAQ cannot be opened (shown by the UI instead of only logged).
enum class UnavailableKind {
    Other,        // open failed for another reason (flaky init, hub still settling): retried
    Busy,         // another MYBENCH or program has the device open
    Permission,   // Linux: no udev rule / no access to the USB node
    Driver,       // Windows: a driver mybench cannot use owns the device (or the mybench-usb service is missing)
    NoDriver,     // Windows: no driver and no mybench-usb service: Set Up installs WinUSB (UAC)
    NiSoftware,   // Windows: NI software is using the myDAQ (or the user gave it to NI): "Use in mybench"
};
// Windows, mybench-usb service (no-ops elsewhere): it is reachable; give the borrowed myDAQs back
// to NI's driver and stop taking them; take them again now, even from a running NI program.
bool usbServiceRunning();
void giveMyDaqsToNi();
void takeMyDaqsNow();

enum class Os { Linux, Windows, MacOs };
Os currentOs();

// Maps a failed open (DeviceError code from the driver/libusb: ACCESS, NOT_SUPPORTED, BUSY, ...)
// to the cause the user can act on. Pure, so it is testable for every OS.
UnavailableKind classifyOpenError(DeviceError::Code code, Os os = currentOs());
QString unavailableId(UnavailableKind kind);      // "busy", "permission", "driver", "setup", "ni", "error"
QString unavailableLabel(UnavailableKind kind);   // 1-3 words for the UI
QString unavailableHint(UnavailableKind kind, Os os = currentOs());   // tooltip text (sentences)
QString unavailableHelpTopic(UnavailableKind kind);   // docs/help page id

struct UnavailableDevice {
    QString location;   // USB port path, stable per port
    UnavailableKind kind = UnavailableKind::Other;
    QString detail;     // the library's message, for the log / tooltip
    bool operator==(const UnavailableDevice& o) const
    {
        return location == o.location && kind == o.kind && detail == o.detail;
    }
};

class DeviceProvider {
public:
    virtual ~DeviceProvider() = default;
    virtual QString name() const = 0;
    virtual QList<DevicePtr> scan() = 0;
    // Attached devices that cannot be opened right now (empty for backends without such a state).
    virtual QList<UnavailableDevice> unavailable() const { return {}; }
};

class DeviceManager : public QObject {
    Q_OBJECT
public:
    static DeviceManager& instance();   // registers the built-in providers on first use

    void addProvider(std::unique_ptr<DeviceProvider> provider);

    QList<DevicePtr> devices() const;
    DevicePtr device(const QString& id) const;   // nullptr if not present
    QList<UnavailableDevice> unavailable() const;   // attached but not openable (all providers)
    DevicePtr defaultDevice() const;             // first real device, else the simulated one

public slots:
    void rescan();   // also runs periodically (hot-plug)

signals:
    void devicesChanged();

private:
    DeviceManager();
    struct Private;
    std::unique_ptr<Private> d;
};

}  // namespace mydaq
