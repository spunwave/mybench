#include "mydaq/device_manager.h"

#include "sim/sim_provider.h"
#ifdef MYDAQ_HAVE_USB
#include "usb/usb_provider.h"
#endif
#ifdef MYDAQ_WINDOWS_LEASE
#include "usb/windows_lease.h"
#endif

#include <QCoreApplication>
#include <QPointer>
#include <QTimer>
#include <QtGlobal>

#include <mutex>
#include <vector>

namespace mydaq {

namespace {

// Hot-plug polling, 2x/s. Cheap: the USB provider's scan() only returns the list its own
// background thread keeps, and the simulator's scan is a flag check.
constexpr int kRescanIntervalMs = 500;

// MYBENCH_FAKE_UNAVAILABLE=driver|permission|busy|error: pretends a myDAQ is attached but cannot
// be opened, to see (and rehearse) what the UI shows without such a machine.
class FakeUnavailableProvider final : public DeviceProvider {
public:
    explicit FakeUnavailableProvider(UnavailableKind kind) : m_kind(kind) {}
    QString name() const override { return QStringLiteral("Fake unavailable"); }
    QList<DevicePtr> scan() override { return {}; }
    QList<UnavailableDevice> unavailable() const override
    {
        return {{QStringLiteral("1-1"), m_kind, QStringLiteral("simulated by MYBENCH_FAKE_UNAVAILABLE")}};
    }

private:
    UnavailableKind m_kind;
};

}  // namespace

struct DeviceManager::Private {
    mutable std::mutex mutex;   // guards providers, devices, deviceIds, timerApp
    std::mutex scanMutex;       // serializes rescans
    std::vector<std::unique_ptr<DeviceProvider>> providers;
    QList<DevicePtr> devices;
    QStringList deviceIds;      // ids of `devices`, same order
    QList<UnavailableDevice> unavailable;
    QPointer<QCoreApplication> timerApp;   // application that owns the rescan timer

    void ensureTimer(DeviceManager* manager);
};

// The periodic rescan runs in the application's thread with a timer owned by the application, so
// it is created lazily once a QCoreApplication exists and disappears with it.
void DeviceManager::Private::ensureTimer(DeviceManager* manager)
{
    QCoreApplication* app = QCoreApplication::instance();
    if (!app)
        return;
    {
        std::lock_guard lock(mutex);
        if (timerApp == app)
            return;
        timerApp = app;
    }
    QMetaObject::invokeMethod(app, [manager, app] {
        auto* timer = new QTimer(app);
        QObject::connect(timer, &QTimer::timeout, manager, &DeviceManager::rescan, Qt::DirectConnection);
        timer->start(kRescanIntervalMs);
    });
}

DeviceManager::DeviceManager() : d(std::make_unique<Private>())
{
#ifdef MYDAQ_HAVE_USB
    d->providers.push_back(makeUsbProvider());
#endif
#ifdef MYDAQ_WINDOWS_LEASE
    // Windows: myDAQs on NI's driver or without one are borrowed through the mybench-usb service.
    if (qEnvironmentVariableIntValue("MYBENCH_NO_USB") == 0)
        d->providers.push_back(makeWindowsLeaseProvider());
#endif
    const QByteArray fake = qgetenv("MYBENCH_FAKE_UNAVAILABLE");
    if (!fake.isEmpty()) {
        const UnavailableKind kind = fake == "driver"       ? UnavailableKind::Driver
                                     : fake == "setup"      ? UnavailableKind::NoDriver
                                     : fake == "ni"         ? UnavailableKind::NiSoftware
                                     : fake == "permission" ? UnavailableKind::Permission
                                     : fake == "busy"       ? UnavailableKind::Busy
                                                            : UnavailableKind::Other;
        d->providers.push_back(std::make_unique<FakeUnavailableProvider>(kind));
    }
    if (qEnvironmentVariableIntValue("MYBENCH_NO_SIM") == 0)
        d->providers.push_back(makeSimProvider());
}

DeviceManager& DeviceManager::instance()
{
    // Never destroyed: devices may be in use by worker threads until the process exits.
    static DeviceManager* const manager = [] {
        auto* m = new DeviceManager;
        m->rescan();
        return m;
    }();
    manager->d->ensureTimer(manager);
    return *manager;
}

void DeviceManager::addProvider(std::unique_ptr<DeviceProvider> provider)
{
    {
        std::lock_guard lock(d->mutex);
        d->providers.push_back(std::move(provider));
    }
    rescan();
}

QList<DevicePtr> DeviceManager::devices() const
{
    std::lock_guard lock(d->mutex);
    return d->devices;
}

DevicePtr DeviceManager::device(const QString& id) const
{
    for (const DevicePtr& device : devices()) {
        if (device->info().id == id)
            return device;
    }
    return nullptr;
}

QList<UnavailableDevice> DeviceManager::unavailable() const
{
    std::lock_guard lock(d->mutex);
    return d->unavailable;
}

bool usbServiceRunning()
{
#ifdef MYDAQ_WINDOWS_LEASE
    return lease::serviceRunning();
#else
    return false;
#endif
}

void giveMyDaqsToNi()
{
#ifdef MYDAQ_WINDOWS_LEASE
    lease::giveBack();
#endif
}

void takeMyDaqsNow()
{
#ifdef MYDAQ_WINDOWS_LEASE
    lease::takeNow();
#endif
}

Os currentOs()
{
#if defined(Q_OS_WIN)
    return Os::Windows;
#elif defined(Q_OS_MACOS)
    return Os::MacOs;
#else
    return Os::Linux;
#endif
}

UnavailableKind classifyOpenError(DeviceError::Code code, Os os)
{
    switch (code) {
    case DeviceError::ResourceBusy:
        return UnavailableKind::Busy;
    case DeviceError::AccessDenied:
        // The driver already turns ACCESS on claim into BUSY; what is left is the open itself.
        if (os == Os::Linux)
            return UnavailableKind::Permission;
        return os == Os::Windows ? UnavailableKind::Driver : UnavailableKind::Busy;
    case DeviceError::NotSupported:
        // Windows: libusb cannot open a device that is not on WinUSB (NI's driver owns it).
        return os == Os::Windows ? UnavailableKind::Driver : UnavailableKind::Other;
    default:
        return UnavailableKind::Other;
    }
}

QString unavailableId(UnavailableKind kind)
{
    switch (kind) {
    case UnavailableKind::Busy: return QStringLiteral("busy");
    case UnavailableKind::Permission: return QStringLiteral("permission");
    case UnavailableKind::Driver: return QStringLiteral("driver");
    case UnavailableKind::NoDriver: return QStringLiteral("setup");
    case UnavailableKind::NiSoftware: return QStringLiteral("ni");
    case UnavailableKind::Other: break;
    }
    return QStringLiteral("error");
}

QString unavailableLabel(UnavailableKind kind)
{
    switch (kind) {
    case UnavailableKind::Busy: return QObject::tr("In use");
    case UnavailableKind::Permission: return QObject::tr("No permission");
    case UnavailableKind::Driver: return QObject::tr("Driver");
    case UnavailableKind::NoDriver: return QObject::tr("Needs setup");
    case UnavailableKind::NiSoftware: return QObject::tr("With NI software");
    case UnavailableKind::Other: break;
    }
    return QObject::tr("Open failed");
}

QString unavailableHint(UnavailableKind kind, Os os)
{
    switch (kind) {
    case UnavailableKind::Busy:
        return os == Os::MacOs
            ? QObject::tr("Another program has the myDAQ open. Close it (another mybench, NI software), then Rescan.")
            : QObject::tr("Another program has the myDAQ open. Close it (another mybench window, NI software), then Rescan.");
    case UnavailableKind::Permission:
        return QObject::tr("This user may not open the myDAQ. Install the mybench udev rule, then re-plug the myDAQ.");
    case UnavailableKind::Driver:
        return QObject::tr("A driver mybench cannot use owns the myDAQ, or the mybench USB service is not running "
                           "(reinstall mybench). See How to Fix.");
    case UnavailableKind::NoDriver:
        return QObject::tr("This myDAQ has no driver yet. Set Up installs Windows' own USB driver for it "
                           "(one administrator prompt, a few seconds).");
    case UnavailableKind::NiSoftware:
        return QObject::tr("NI software has the myDAQ. mybench takes it as soon as that software is closed; "
                           "Use in mybench takes it now (that program loses the myDAQ).");
    case UnavailableKind::Other: break;
    }
    return QObject::tr("The myDAQ did not respond. Re-plug it; mybench retries on its own.");
}

QString unavailableHelpTopic(UnavailableKind) { return QStringLiteral("device"); }

DevicePtr DeviceManager::defaultDevice() const
{
    const QList<DevicePtr> all = devices();
    for (const DevicePtr& device : all) {
        if (!device->info().simulated)
            return device;
    }
    return all.isEmpty() ? nullptr : all.front();
}

void DeviceManager::rescan()
{
    std::lock_guard scanLock(d->scanMutex);
    std::vector<DeviceProvider*> providers;
    {
        std::lock_guard lock(d->mutex);
        for (const auto& p : d->providers)
            providers.push_back(p.get());
    }

    QList<DevicePtr> found;
    QStringList ids;
    for (DeviceProvider* provider : providers) {
        try {
            for (const DevicePtr& device : provider->scan()) {
                const QString id = device->info().id;
                if (!ids.contains(id)) {
                    ids << id;
                    found << device;
                }
            }
        } catch (const std::exception& e) {
            qWarning("Device scan failed (%s): %s", qPrintable(provider->name()), e.what());
        }
    }

    QList<UnavailableDevice> unavailable;
    for (DeviceProvider* provider : providers) {
        try {
            unavailable << provider->unavailable();
        } catch (const std::exception& e) {
            qWarning("Device scan failed (%s): %s", qPrintable(provider->name()), e.what());
        }
    }

    bool changed = false;
    {
        std::lock_guard lock(d->mutex);
        changed = d->deviceIds != ids || d->unavailable != unavailable;
        d->devices = found;
        d->deviceIds = ids;
        d->unavailable = unavailable;
    }
    if (changed)
        emit devicesChanged();
}

}  // namespace mydaq

// Compiled here so the moc code sees the complete Private type (implicit destructor of the pimpl).
#include "mydaq/moc_device_manager.cpp"
