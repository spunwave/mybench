#include "windows_lease.h"

#include <libmybench/mydaq.h>

#include <QLoggingCategory>

#include <windows.h>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <map>
#include <mutex>
#include <optional>
#include <thread>

Q_LOGGING_CATEGORY(lcLease, "mybench.usb.lease")

namespace mydaq {
namespace {

using namespace std::chrono_literals;
using Clock = std::chrono::steady_clock;

// The connection to \\.\pipe\mybench-usb. Lines out, reply lines up to "end". The connection is
// the lease: the service gives everything back when it closes.
class ServicePipe {
public:
    ~ServicePipe() { close(); }

    std::optional<QStringList> call(const QByteArray& command)
    {
        std::lock_guard lock(m_mutex);
        for (int attempt = 0; attempt < 2; ++attempt) {
            if (m_pipe == INVALID_HANDLE_VALUE && !open())
                return std::nullopt;
            const QByteArray line = command + '\n';
            DWORD put = 0;
            if (WriteFile(m_pipe, line.constData(), DWORD(line.size()), &put, nullptr)) {
                if (auto reply = readReply())
                    return reply;
            }
            close();   // the service restarted: reconnect once
        }
        return std::nullopt;
    }

private:
    bool open()
    {
        const wchar_t* name = L"\\\\.\\pipe\\mybench-usb";
        m_pipe = CreateFileW(name, GENERIC_READ | GENERIC_WRITE, 0, nullptr, OPEN_EXISTING, 0, nullptr);
        if (m_pipe == INVALID_HANDLE_VALUE && GetLastError() == ERROR_PIPE_BUSY && WaitNamedPipeW(name, 2000))
            m_pipe = CreateFileW(name, GENERIC_READ | GENERIC_WRITE, 0, nullptr, OPEN_EXISTING, 0, nullptr);
        return m_pipe != INVALID_HANDLE_VALUE;
    }
    void close()
    {
        if (m_pipe != INVALID_HANDLE_VALUE)
            CloseHandle(m_pipe);
        m_pipe = INVALID_HANDLE_VALUE;
        m_buffer.clear();
    }
    std::optional<QStringList> readReply()
    {
        QStringList lines;
        for (;;) {
            int nl;
            while ((nl = m_buffer.indexOf('\n')) >= 0) {
                const QString line = QString::fromUtf8(m_buffer.left(nl)).trimmed();
                m_buffer.remove(0, nl + 1);
                if (line == QLatin1String("end"))
                    return lines;
                lines << line;
            }
            char chunk[4096];
            DWORD got = 0;
            if (!ReadFile(m_pipe, chunk, sizeof chunk, &got, nullptr) || !got)
                return std::nullopt;
            m_buffer.append(chunk, int(got));
        }
    }

    std::mutex m_mutex;
    HANDLE m_pipe = INVALID_HANDLE_VALUE;
    QByteArray m_buffer;
};

struct LeaseState {
    ServicePipe pipe;
    std::atomic<bool> serviceUp{false};
    std::atomic<bool> paused{false};   // the user gave the myDAQs to NI
    std::atomic<bool> force{false};    // the user asked to take them now
    std::mutex mutex;
    std::condition_variable wake;
    bool kick = false;
};

LeaseState& state()
{
    static LeaseState s;
    return s;
}

QString instanceOf(const QString& serial) { return QStringLiteral("USB\\VID_3923&PID_755B\\") + serial; }

class WindowsLeaseProvider final : public DeviceProvider {
public:
    WindowsLeaseProvider()
    {
        mydaq_context* ctx = nullptr;
        if (mydaq_context_new_no_usb(&ctx) == MYDAQ_OK)
            m_context.reset(ctx);
    }
    ~WindowsLeaseProvider() override
    {
        {
            std::lock_guard lock(state().mutex);
            m_stop = true;
            state().kick = true;
        }
        state().wake.notify_all();
        if (m_thread.joinable())
            m_thread.join();
    }

    QString name() const override { return QStringLiteral("Windows USB lease"); }

    QList<DevicePtr> scan() override
    {
        std::lock_guard lock(m_mutex);
        if (!m_thread.joinable() && !m_stop)
            m_thread = std::thread([this] { run(); });
        return {};
    }

    QList<UnavailableDevice> unavailable() const override
    {
        std::lock_guard lock(m_mutex);
        return m_unavailable;
    }

private:
    void run()
    {
        for (;;) {
            try {
                poll();
            } catch (const std::exception& e) {
                qCWarning(lcLease, "myDAQ lease: %s", e.what());
            }
            std::unique_lock lock(state().mutex);
            state().wake.wait_for(lock, 1s, [] { return state().kick; });
            state().kick = false;
            if (m_stop)
                return;
        }
    }

    void poll()
    {
        mydaq_unusable_desc list[8];
        size_t count = 0;
        if (!m_context || mydaq_find_unusable(m_context.get(), list, 8, &count) != MYDAQ_OK)
            count = 0;
        QList<UnavailableDevice> unavailable;
        std::map<QString, mydaq_unusable_reason> wanted;   // serial -> NI driver / no driver
        for (size_t i = 0; i < count && i < 8; ++i) {
            const QString instance = QString::fromLatin1(list[i].instance_id);
            if (list[i].reason == MYDAQ_UNUSABLE_NI_DRIVER || list[i].reason == MYDAQ_UNUSABLE_NO_DRIVER)
                wanted[instance.section(u'\\', -1).toUpper()] = mydaq_unusable_reason(list[i].reason);
            else
                unavailable.append({instance, UnavailableKind::Driver,
                                    QStringLiteral("The driver \"%1\" owns the myDAQ").arg(QString::fromLatin1(list[i].service))});
        }
        LeaseState& s = state();
        const bool force = s.force.exchange(false);
        if (force)
            s.paused = false;
        if (wanted.empty()) {
            publish(unavailable);
            return;
        }
        if (s.paused) {
            for (const auto& [serial, reason] : wanted)
                unavailable.append({instanceOf(serial), UnavailableKind::NiSoftware,
                                    QStringLiteral("Given to NI software from mybench")});
            publish(unavailable);
            return;
        }
        if (!force && Clock::now() < m_nextTry) {
            unavailable.append(m_lastLeaseProblems);
            publish(unavailable);
            return;
        }

        const std::optional<QStringList> reply = s.pipe.call(force ? "take force" : "take");
        const bool up = reply.has_value();
        if (up != s.serviceUp.exchange(up))
            qCInfo(lcLease, up ? "mybench-usb service reached" : "mybench-usb service not running");
        QList<UnavailableDevice> problems;
        std::chrono::milliseconds retry = 2s;
        if (!up) {
            retry = 5s;
            for (const auto& [serial, reason] : wanted) {
                if (reason == MYDAQ_UNUSABLE_NO_DRIVER)
                    problems.append({instanceOf(serial), UnavailableKind::NoDriver,
                                     QStringLiteral("The myDAQ has no driver, and the mybench USB service is not running")});
                else
                    problems.append({instanceOf(serial), UnavailableKind::Driver,
                                     QStringLiteral("NI's driver owns the myDAQ, and the mybench USB service is not running")});
            }
        } else {
            for (const QString& line : *reply) {
                const QString verb = line.section(u' ', 0, 0);
                const QString serial = line.section(u' ', 1, 1).toUpper();
                const QString detail = line.section(u' ', 2);
                if (!wanted.count(serial) && verb != QLatin1String("ok"))
                    continue;
                if (verb == QLatin1String("ok")) {
                    qCInfo(lcLease, "myDAQ %s: %s", qPrintable(serial), qPrintable(detail));
                } else if (verb == QLatin1String("busy")) {
                    problems.append({instanceOf(serial), UnavailableKind::NiSoftware,
                                     QStringLiteral("In use by %1").arg(detail)});
                } else if (verb == QLatin1String("other")) {
                    problems.append({instanceOf(serial), UnavailableKind::Driver,
                                     QStringLiteral("The driver \"%1\" owns the myDAQ").arg(detail)});
                } else {
                    retry = 10s;
                    problems.append({instanceOf(serial), UnavailableKind::Other, detail});
                    qCWarning(lcLease, "myDAQ %s: %s", qPrintable(serial), qPrintable(line));
                }
            }
        }
        m_nextTry = Clock::now() + retry;
        m_lastLeaseProblems = problems;
        unavailable.append(problems);
        publish(unavailable);
    }

    void publish(const QList<UnavailableDevice>& unavailable)
    {
        std::lock_guard lock(m_mutex);
        m_unavailable = unavailable;
    }

    struct ContextFree {
        void operator()(mydaq_context* c) const { mydaq_context_free(c); }
    };
    std::unique_ptr<mydaq_context, ContextFree> m_context;
    mutable std::mutex m_mutex;
    QList<UnavailableDevice> m_unavailable;
    QList<UnavailableDevice> m_lastLeaseProblems;
    Clock::time_point m_nextTry{};
    std::thread m_thread;
    std::atomic<bool> m_stop{false};
};

void kick()
{
    {
        std::lock_guard lock(state().mutex);
        state().kick = true;
    }
    state().wake.notify_all();
}

}  // namespace

std::unique_ptr<DeviceProvider> makeWindowsLeaseProvider() { return std::make_unique<WindowsLeaseProvider>(); }

namespace lease {
bool serviceRunning() { return state().serviceUp; }

void giveBack()
{
    state().paused = true;
    if (state().pipe.call("giveback"))
        qCInfo(lcLease, "myDAQs given back to NI's driver");
    kick();
}

void takeNow()
{
    state().force = true;
    kick();
}
}  // namespace lease

}  // namespace mydaq
