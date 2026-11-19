#include "mybench/devicehub.h"

#include "mybench/eventlog.h"
#include "mybench/instrumentcontroller.h"
#include "mybench/instrumentregistry.h"
#include "mybench/notifications.h"

#include <mydaq/device_manager.h>
#include <mydaq/sim_device.h>

#include <QCoreApplication>
#include <QDir>
#include <QElapsedTimer>
#include <QFileInfo>
#include <QJSEngine>
#include <QPointer>
#include <QSettings>
#include <QTimer>

#include <algorithm>
#include <cmath>
#include <thread>

#ifdef Q_OS_WIN
#include <qt_windows.h>
#include <shellapi.h>
#endif

using namespace Qt::StringLiterals;

namespace mybench {

namespace {

const QString kCurrentKey = u"device/current"_s;

}  // namespace

// --- DeviceListModel -----------------------------------------------------------------------

DeviceListModel::DeviceListModel(QObject* parent) : QAbstractListModel(parent) {}

void DeviceListModel::setEntries(const QList<Entry>& entries)
{
    const bool sameShape = [&] {
        if (entries.size() != m_entries.size())
            return false;
        for (qsizetype i = 0; i < entries.size(); ++i) {
            if (entries[i].info.id != m_entries[i].info.id)
                return false;
        }
        return true;
    }();
    if (sameShape) {
        m_entries = entries;
        if (!m_entries.isEmpty())
            emit dataChanged(index(0), index(int(m_entries.size()) - 1));
        return;
    }
    beginResetModel();
    m_entries = entries;
    endResetModel();
    emit countChanged();
}

int DeviceListModel::indexOf(const QString& deviceId) const
{
    for (qsizetype i = 0; i < m_entries.size(); ++i) {
        if (m_entries[i].info.id == deviceId)
            return int(i);
    }
    return -1;
}

QString DeviceListModel::deviceIdAt(int row) const
{
    return row >= 0 && row < m_entries.size() ? m_entries[row].info.id : QString();
}

int DeviceListModel::rowCount(const QModelIndex& parent) const
{
    return parent.isValid() ? 0 : int(m_entries.size());
}

QVariant DeviceListModel::data(const QModelIndex& index, int role) const
{
    if (!index.isValid() || index.row() >= m_entries.size())
        return {};
    const Entry& entry = m_entries[index.row()];
    switch (role) {
    case Qt::DisplayRole:
    case DisplayNameRole:
        return entry.connected ? entry.info.name : tr("%1 (disconnected)").arg(entry.info.name);
    case DeviceIdRole:
        return entry.info.id;
    case NameRole:
        return entry.info.name;
    case ProductTypeRole:
        return entry.info.productType;
    case SerialNumberRole:
        return entry.info.serialNumber;
    case SimulatedRole:
        return entry.info.simulated;
    case ConnectedRole:
        return entry.connected;
    default:
        return {};
    }
}

QHash<int, QByteArray> DeviceListModel::roleNames() const
{
    return {
        {DeviceIdRole, "deviceId"},
        {NameRole, "name"},
        {DisplayNameRole, "displayName"},
        {ProductTypeRole, "productType"},
        {SerialNumberRole, "serialNumber"},
        {SimulatedRole, "simulated"},
        {ConnectedRole, "connected"},
    };
}

// --- DeviceHub -----------------------------------------------------------------------------

DeviceHub::DeviceHub(QObject* parent) : QObject(parent), m_model(new DeviceListModel(this))
{
    mydaq::DeviceManager& manager = mydaq::DeviceManager::instance();
    m_simulator = std::dynamic_pointer_cast<mydaq::SimDevice>(manager.device(u"sim:0"_s));
    connect(&manager, &mydaq::DeviceManager::devicesChanged, this, &DeviceHub::refresh);

    for (const mydaq::DevicePtr& device : manager.devices())
        m_presentIds.append(device->info().id);

    const QString stored = QSettings().value(kCurrentKey).toString();
    QString id;
    if (!stored.isEmpty() && manager.device(stored))
        id = stored;
    else if (const mydaq::DevicePtr device = manager.defaultDevice())
        id = device->info().id;
    connect(this, &DeviceHub::currentChanged, this, &DeviceHub::updateCapabilities);
    connect(this, &DeviceHub::connectionChanged, this, &DeviceHub::updateCapabilities);
    setCurrent(id, false);
    refresh();
    updateCapabilities();
}

void DeviceHub::updateCapabilities()
{
    const mydaq::DevicePtr current = device();
    QStringList list;
    if (current)
        list = current->unsupportedFeatures();
    else if (m_unsupportedFor == m_currentId)
        list = m_unsupported;   // unplugged: keep what the device said
    m_unsupportedFor = m_currentId;
    if (list == m_unsupported)
        return;
    m_unsupported = list;
    emit capabilitiesChanged();
}

QStringList DeviceHub::simulatorUnsupportedFeatures() const
{
    return m_simulator ? m_simulator->unsupportedFeatures() : QStringList();
}

void DeviceHub::setSimulatorUnsupportedFeatures(const QStringList& features)
{
    if (!m_simulator || m_simulator->unsupportedFeatures() == features)
        return;
    m_simulator->setUnsupportedFeatures(features);
    emit simulatorChanged();
    updateCapabilities();
}

QString DeviceHub::unsupportedReason(const QString& feature) const
{
    if (supports(feature))
        return {};
    return tr("Not supported by %1").arg(backend());
}

DeviceHub* DeviceHub::instance()
{
    static DeviceHub* const hub = new DeviceHub;
    return hub;
}

DeviceHub* DeviceHub::create(QQmlEngine*, QJSEngine*)
{
    DeviceHub* hub = instance();
    QJSEngine::setObjectOwnership(hub, QJSEngine::CppOwnership);
    return hub;
}

mydaq::DevicePtr DeviceHub::device() const
{
    std::lock_guard lock(m_mutex);
    return m_device;
}

mydaq::DeviceInfo DeviceHub::info() const
{
    return m_currentInfo;
}

int DeviceHub::currentIndex() const
{
    return m_model->indexOf(m_currentId);
}

DeviceHub::ConnectionState DeviceHub::connectionState() const
{
    if (m_resetting)
        return Resetting;
    if (m_currentId.isEmpty())
        return NoDevice;
    const mydaq::DevicePtr current = device();
    return current && current->isConnected() ? Connected : Disconnected;
}

void DeviceHub::setCurrent(const QString& deviceId, bool persist)
{
    mydaq::DeviceManager& manager = mydaq::DeviceManager::instance();
    const mydaq::DevicePtr found = deviceId.isEmpty() ? nullptr : manager.device(deviceId);
    if (deviceId != m_currentId && !m_selfTestChecks.isEmpty()) {   // results belong to the old device
        m_selfTestChecks.clear();
        emit selfTestChanged();
    }
    m_currentId = deviceId;
    if (found)
        m_currentInfo = found->info();
    else if (deviceId.isEmpty())
        m_currentInfo = {};
    {
        std::lock_guard lock(m_mutex);
        m_device = found;
    }
    if (persist)
        QSettings().setValue(kCurrentKey, deviceId);
    if (const auto toast = m_connectedToasts.take(deviceId); toast != 0)
        Notifications::instance()->dismiss(toast);   // "<name> connected - Switch" is stale now
    emit currentChanged();
    emit connectionChanged();
}

void DeviceHub::select(const QString& deviceId)
{
    if (deviceId == m_currentId || m_resetting)
        return;
    if (!mydaq::DeviceManager::instance().device(deviceId))
        return;
    InstrumentRegistry::instance()->stopAll();
    setCurrent(deviceId, true);
    refresh();
    EventLog::log(EventLog::Info, u"device"_s, tr("Selected %1").arg(m_currentInfo.name));
}

void DeviceHub::selectIndex(int row)
{
    select(m_model->deviceIdAt(row));
}

void DeviceHub::rescan()
{
    mydaq::DeviceManager::instance().rescan();
}

void DeviceHub::refresh()
{
    mydaq::DeviceManager& manager = mydaq::DeviceManager::instance();
    const QList<mydaq::DevicePtr> devices = manager.devices();

    QList<DeviceListModel::Entry> entries;
    QStringList ids;
    QHash<QString, QString> names;
    for (const mydaq::DevicePtr& device : devices) {
        const mydaq::DeviceInfo info = device->info();
        ids.append(info.id);
        names.insert(info.id, info.name);
        entries.append({info, device->isConnected()});
    }

    // Hot-plug notifications.
    const QStringList previous = m_presentIds;
    m_presentIds = ids;
    for (const QString& id : ids) {
        if (previous.contains(id))
            continue;
        const QString name = names.value(id);
        EventLog::log(EventLog::Info, u"device"_s, tr("%1 connected").arg(name));
        emit deviceArrived(id, name);
        const mydaq::DevicePtr arrived = manager.device(id);
        const bool real = arrived && !arrived->info().simulated;
        QPointer<DeviceHub> self(this);
        if (id == m_currentId) {
            Notifications::instance()->show(Notifications::Success, tr("%1 reconnected").arg(name),
                                            {}, {}, {}, u"device"_s);
        } else if (real && m_currentInfo.simulated && !previous.isEmpty()
                   && !InstrumentRegistry::instance()->anyRunning()) {
            // A real myDAQ appears while the simulator is used and nothing runs: use it.
            const QString before = m_currentId;
            QMetaObject::invokeMethod(this, [self, id, before, name] {
                if (!self)
                    return;
                self->select(id);
                Notifications::instance()->show(Notifications::Success, tr("Using %1").arg(name), {},
                                                tr("Undo"), [self, before] { if (self) self->select(before); },
                                                u"device"_s);
            }, Qt::QueuedConnection);
        } else {
            // Offered only if it is still not the selected device once the current event has been
            // handled (a startup option or a session may select it right away), and withdrawn
            // when it becomes the selection.
            QMetaObject::invokeMethod(this, [self, id, name] {
                if (!self || self->m_currentId == id || !self->m_presentIds.contains(id))
                    return;
                self->m_connectedToasts.insert(id, Notifications::instance()->show(
                    Notifications::Info, tr("%1 connected").arg(name), {}, tr("Switch"),
                    [self, id] { if (self) self->select(id); }, u"device"_s));
            }, Qt::QueuedConnection);
        }
    }
    bool currentLost = false;
    for (const QString& id : previous) {
        if (ids.contains(id))
            continue;
        const bool isCurrent = id == m_currentId;
        currentLost = currentLost || isCurrent;
        const QString name = isCurrent ? m_currentInfo.name : id;
        EventLog::log(isCurrent ? EventLog::Warning : EventLog::Info, u"device"_s, tr("%1 disconnected").arg(name));
        emit deviceLost(id, name);
        if (isCurrent) {
            Notifications::instance()->show(Notifications::Error, tr("%1 disconnected").arg(name),
                                            {}, {}, {}, u"device"_s);
        }
    }

    // Attached but not openable (wrong driver, no permission, busy): shown, and logged once.
    {
        QVariantList list;
        QStringList locations;
        for (const mydaq::UnavailableDevice& u : manager.unavailable()) {
            QVariantMap entry;
            entry.insert(u"location"_s, u.location);
            entry.insert(u"kind"_s, mydaq::unavailableId(u.kind));
            entry.insert(u"label"_s, mydaq::unavailableLabel(u.kind));
            entry.insert(u"hint"_s, mydaq::unavailableHint(u.kind));
            entry.insert(u"detail"_s, u.detail);
            entry.insert(u"helpTopic"_s, mydaq::unavailableHelpTopic(u.kind));
            list.append(entry);
            locations.append(u.location + u'/' + mydaq::unavailableId(u.kind));
            if (!m_unavailableLogged.contains(locations.last()))
                EventLog::log(EventLog::Warning, u"device"_s,
                              tr("myDAQ at USB %1 not available (%2)").arg(u.location, mydaq::unavailableLabel(u.kind)),
                              u.detail);
        }
        m_unavailableLogged = locations;
        if (list != m_unavailable) {
            m_unavailable = list;
            emit unavailableChanged();
        }
    }

    // The selection stays listed while unplugged.
    if (!m_currentId.isEmpty() && !ids.contains(m_currentId))
        entries.append({m_currentInfo, false});

    // First device ever (nothing was selected): select it.
    if (m_currentId.isEmpty() && !devices.isEmpty()) {
        m_model->setEntries(entries);
        if (const mydaq::DevicePtr fallback = manager.defaultDevice())
            setCurrent(fallback->info().id, false);
        return;
    }

    const ConnectionState before = connectionState();
    const mydaq::DevicePtr previousDevice = device();
    const mydaq::DevicePtr current = m_currentId.isEmpty() ? nullptr : manager.device(m_currentId);
    {
        std::lock_guard lock(m_mutex);
        m_device = current;
    }
    if (current)
        m_currentInfo = current->info();
    const int indexBefore = currentIndex();
    m_model->setEntries(entries);

    if (currentLost) {
        for (InstrumentController* controller : InstrumentRegistry::instance()->controllers())
            controller->deviceDisconnected();
    }
    // The state alone is not enough: an unplugged device already reports itself disconnected before
    // the provider drops it, so "Disconnected" would otherwise never be announced (stale
    // "Connected" in the Overview and the status bar); likewise a re-plugged one is a new object.
    if (connectionState() != before || current != previousDevice)
        emit connectionChanged();
    if (currentIndex() != indexBefore || currentLost)
        emit currentChanged();
}

void DeviceHub::reset()
{
    if (m_resetting)
        return;
    const mydaq::DevicePtr current = device();
    if (!current) {
        Notifications::instance()->show(Notifications::Warning, tr("No device"));
        return;
    }
    m_resetting = true;
    emit connectionChanged();

    InstrumentRegistry* registry = InstrumentRegistry::instance();
    registry->stopAll();

    // Reset once every instrument released the hardware (bounded wait), off the UI thread.
    auto* waiter = new QTimer(this);
    waiter->setInterval(20);
    auto started = std::make_shared<QElapsedTimer>();
    started->start();
    QPointer<DeviceHub> self(this);
    connect(waiter, &QTimer::timeout, this, [self, waiter, started, current, registry] {
        if (registry->anyRunning() && started->elapsed() < 3000)
            return;
        waiter->stop();
        waiter->deleteLater();
        DeviceHub* hub = self.data();   // the hub is a process-wide singleton, never destroyed
        std::thread([hub, current] {
            bool ok = true;
            QString error;
            QString details;
            try {
                current->reset();
            } catch (const mydaq::DeviceError& e) {
                ok = false;
                error = e.message();
                details = EventLog::errorDetails(e.code(), e.message());
            } catch (const std::exception& e) {
                ok = false;
                error = QString::fromUtf8(e.what());
            }
            QMetaObject::invokeMethod(hub, [hub, ok, error, details] {
                hub->m_resetting = false;
                emit hub->connectionChanged();
                emit hub->resetFinished(ok, error);
                if (ok) {
                    EventLog::log(EventLog::Info, u"device"_s, tr("Device reset"));
                    Notifications::instance()->show(Notifications::Success, tr("Device reset"),
                                                    tr("Outputs at 0 V"), {}, {}, u"device"_s);
                } else {
                    EventLog::log(EventLog::Error, u"device"_s, tr("Reset failed: %1").arg(error), details);
                    Notifications::instance()->show(Notifications::Error, tr("Reset failed"), error, {}, {}, u"device"_s);
                }
            }, Qt::QueuedConnection);
        }).detach();
    });
    waiter->start();
}

void DeviceHub::selfTest()
{
    const mydaq::DevicePtr current = device();
    if (m_selfTesting || m_resetting || !current)
        return;
    m_selfTesting = true;
    m_selfTestChecks.clear();
    emit selfTestChanged();
    InstrumentRegistry* registry = InstrumentRegistry::instance();
    registry->stopAll();
    auto* waiter = new QTimer(this);
    waiter->setInterval(20);
    auto started = std::make_shared<QElapsedTimer>();
    started->start();
    const QString name = m_currentInfo.name;
    connect(waiter, &QTimer::timeout, this, [this, waiter, started, current, registry, name] {
        if (registry->anyRunning() && started->elapsed() < 3000)
            return;
        waiter->stop();
        waiter->deleteLater();
        std::thread([this, current, name] {
            mydaq::SelfTestResult result;
            try {
                result = current->selfTest();
            } catch (const std::exception& e) {
                result.checks.push_back({tr("Self-test"), false, QString::fromUtf8(e.what())});
            }
            QMetaObject::invokeMethod(this, [this, result, name] {
                m_selfTesting = false;
                m_selfTestChecks.clear();
                QStringList lines;
                for (const auto& c : result.checks) {
                    m_selfTestChecks.append(QVariantMap{{u"name"_s, c.name}, {u"ok"_s, c.ok}, {u"detail"_s, c.detail}});
                    lines << u"%1: %2 (%3)"_s.arg(c.name, c.ok ? u"OK"_s : u"FAILED"_s, c.detail);
                }
                const bool passed = result.passed();
                EventLog::log(passed ? EventLog::Info : EventLog::Warning, u"device"_s,
                              passed ? tr("Self-test of %1 passed").arg(name) : tr("Self-test of %1 failed").arg(name), lines.join(u'\n'));
                Notifications::instance()->show(passed ? Notifications::Success : Notifications::Warning,
                                                passed ? tr("Self-test passed") : tr("Self-test failed"), name, {}, {}, u"device"_s);
                emit selfTestChanged();
                emit selfTestFinished(passed);
            }, Qt::QueuedConnection);
        }).detach();
    });
    waiter->start();
}

double DeviceHub::maxAiRate() const
{
    const mydaq::DevicePtr current = device();
    return current ? current->maxAiRate() : 0.0;
}

double DeviceHub::maxAoRate() const
{
    const mydaq::DevicePtr current = device();
    return current ? current->maxAoRate() : 0.0;
}

QString DeviceHub::backend() const
{
    if (m_currentId.isEmpty())
        return {};
    if (!m_currentInfo.backend.isEmpty())
        return m_currentInfo.backend;
    return m_currentInfo.simulated ? tr("Simulator") : u"USB"_s;
}

// --- Windows driver (mybench-usb-setup.exe) ---------------------------------------------------

#ifdef Q_OS_WIN
namespace {
QString driverToolPath()
{
    return QDir(QCoreApplication::applicationDirPath()).filePath(u"mybench-usb-setup.exe"_s);
}
}  // namespace
#endif

bool DeviceHub::driverSetupAvailable() const
{
#ifdef Q_OS_WIN
    return QFileInfo::exists(driverToolPath());
#else
    return false;
#endif
}

bool DeviceHub::canReleaseToNi() const
{
    return mydaq::usbServiceRunning() && !m_currentId.isEmpty() && !m_currentInfo.simulated;
}

void DeviceHub::setUpDriver()
{
    // With the mybench-usb service: take the myDAQ now ("Use in mybench"), even from NI software.
    if (mydaq::usbServiceRunning()) {
        EventLog::log(EventLog::Info, u"device"_s, tr("Taking the myDAQ from NI software"));
        mydaq::takeMyDaqsNow();
        return;
    }
    runDriverTool(u"take"_s);   // no service (damaged install): the tool, with one UAC prompt
}

void DeviceHub::releaseDriver()
{
    if (!mydaq::usbServiceRunning()) {
        runDriverTool(u"release"_s);
        return;
    }
    InstrumentRegistry::instance()->stopAll();
    std::thread([] { mydaq::giveMyDaqsToNi(); }).detach();
    const QString message = tr("The myDAQ is with NI software now. Use in mybench takes it back.");
    EventLog::log(EventLog::Info, u"device"_s, message);
    Notifications::instance()->show(Notifications::Success, tr("Given to NI software"), message, {}, {}, u"device"_s);
}

void DeviceHub::runDriverTool(const QString& command)
{
    if (m_driverSetupRunning)
        return;
#ifdef Q_OS_WIN
    if (!driverSetupAvailable()) {
        emit driverSetupFinished(false, tr("mybench-usb-setup.exe is missing: reinstall mybench"));
        return;
    }
    m_driverSetupRunning = true;
    emit driverSetupChanged();
    EventLog::log(EventLog::Info, u"device"_s,
                  command == u"take"_s ? tr("Installing Windows' USB driver for the myDAQ") : tr("Giving the myDAQ back to NI's driver"));
    QPointer<DeviceHub> self(this);
    std::thread([self, command, tool = driverToolPath()] {
        const std::wstring file = QDir::toNativeSeparators(tool).toStdWString();
        const std::wstring args = command.toStdWString();
        SHELLEXECUTEINFOW info{};
        info.cbSize = sizeof info;
        info.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_NOASYNC;
        info.lpVerb = L"runas";   // one UAC prompt; the tool's manifest asks for it too
        info.lpFile = file.c_str();
        info.lpParameters = args.c_str();
        info.nShow = SW_HIDE;
        bool ok = false;
        QString message;
        if (!ShellExecuteExW(&info)) {
            message = GetLastError() == ERROR_CANCELLED ? DeviceHub::tr("Cancelled: Windows asked for administrator rights")
                                                            : DeviceHub::tr("Could not start mybench-usb-setup.exe (error %1)").arg(GetLastError());
        } else {
            DWORD code = 1;
            if (info.hProcess) {
                WaitForSingleObject(info.hProcess, 120000);
                GetExitCodeProcess(info.hProcess, &code);
                CloseHandle(info.hProcess);
            }
            ok = code == 0;
            message = ok ? (command == u"take"_s ? DeviceHub::tr("The myDAQ is set up") : DeviceHub::tr("The myDAQ is back with NI's driver"))
                         : DeviceHub::tr("The driver setup failed (code %1); details: run mybench-usb-setup.exe status").arg(code);
        }
        QMetaObject::invokeMethod(qApp, [self, ok, message] {
            if (!self)
                return;
            self->m_driverSetupRunning = false;
            emit self->driverSetupChanged();
            EventLog::log(ok ? EventLog::Info : EventLog::Warning, u"device"_s, message);
            Notifications::instance()->show(ok ? Notifications::Success : Notifications::Warning, message);
            emit self->driverSetupFinished(ok, message);
            self->rescan();
        });
    }).detach();
#else
    Q_UNUSED(command);
    emit driverSetupFinished(false, tr("Only needed on Windows"));
#endif
}

// --- Simulator -----------------------------------------------------------------------------

bool DeviceHub::simulatorPlugged() const
{
    return m_simulator && m_simulator->isConnected();
}

void DeviceHub::setSimulatorPlugged(bool plugged)
{
    if (!m_simulator || plugged == simulatorPlugged())
        return;
    m_simulator->setConnected(plugged);
    emit simulatorChanged();
    rescan();
}

double DeviceHub::simulatorNoiseRms() const
{
    return m_simulator ? m_simulator->noiseRms() : 0.0;
}

void DeviceHub::setSimulatorNoiseRms(double volts)
{
    if (!m_simulator || volts == simulatorNoiseRms())
        return;
    m_simulator->setNoiseRms(volts);
    emit simulatorChanged();
}

double DeviceHub::simulatorRcCutoff() const
{
    return m_simulator ? m_simulator->rcCutoff() : 0.0;
}

void DeviceHub::setSimulatorRcCutoff(double hertz)
{
    if (!m_simulator || hertz == simulatorRcCutoff())
        return;
    m_simulator->setRcCutoff(hertz);
    emit simulatorChanged();
}

bool DeviceHub::simulatorDmmOpenCircuit() const
{
    return m_simulator && m_simulator->dmmOpenCircuit();
}

void DeviceHub::setSimulatorDmmOpenCircuit(bool open)
{
    if (!m_simulator || open == simulatorDmmOpenCircuit())
        return;
    m_simulator->setDmmOpenCircuit(open);
    emit simulatorChanged();
}

// Test signals of undriven inputs and DMM input values (SimulatorDialog).

namespace {

constexpr int kSimAiChannels = 4;    // mydaq::AiChannel
constexpr int kSimDmmFunctions = 7;  // mydaq::DmmFunction

}  // namespace

QVariantList DeviceHub::simulatorTestSignals() const
{
    QVariantList list;
    if (!m_simulator)
        return list;
    for (int channel = 0; channel < kSimAiChannels; ++channel) {
        const mydaq::SimTestSignal signal = m_simulator->testSignal(mydaq::AiChannel(channel));
        QVariantMap map;
        map.insert(u"waveform"_s, int(signal.waveform));
        map.insert(u"frequency"_s, signal.frequency);
        map.insert(u"amplitude"_s, signal.amplitude);
        map.insert(u"offset"_s, signal.offset);
        map.insert(u"dutyCycle"_s, signal.dutyCycle);
        list.append(map);
    }
    return list;
}

void DeviceHub::setSimulatorTestSignal(int channel, const QVariantMap& changes)
{
    if (!m_simulator || channel < 0 || channel >= kSimAiChannels)
        return;
    const auto ch = mydaq::AiChannel(channel);
    mydaq::SimTestSignal signal = m_simulator->testSignal(ch);   // keeps the harmonics
    if (changes.contains(u"waveform"_s)) {
        const int waveform = changes.value(u"waveform"_s).toInt();
        if (waveform >= int(mydaq::dsp::Waveform::Sine) && waveform <= int(mydaq::dsp::Waveform::Noise))
            signal.waveform = mydaq::dsp::Waveform(waveform);
    }
    auto number = [&](const QString& key, double& target, double low, double high) {
        bool ok = false;
        const double value = changes.value(key).toDouble(&ok);
        if (changes.contains(key) && ok && std::isfinite(value))
            target = std::clamp(value, low, high);
    };
    number(u"frequency"_s, signal.frequency, 0.001, 100000.0);
    number(u"amplitude"_s, signal.amplitude, 0.0, 20.0);
    number(u"offset"_s, signal.offset, -10.0, 10.0);
    number(u"dutyCycle"_s, signal.dutyCycle, 0.01, 0.99);
    m_simulator->setTestSignal(ch, signal);
    emit simulatorChanged();
}

QVariantList DeviceHub::simulatorDmmValues() const
{
    QVariantList list;
    if (!m_simulator)
        return list;
    for (int function = 0; function < kSimDmmFunctions; ++function)
        list.append(m_simulator->dmmValue(mydaq::DmmFunction(function)));
    return list;
}

void DeviceHub::setSimulatorDmmValue(int function, double value)
{
    if (!m_simulator || function < 0 || function >= kSimDmmFunctions || !std::isfinite(value))
        return;
    if (m_simulator->dmmValue(mydaq::DmmFunction(function)) == value)
        return;
    m_simulator->setDmmValue(mydaq::DmmFunction(function), value);
    emit simulatorChanged();
}

}  // namespace mybench
