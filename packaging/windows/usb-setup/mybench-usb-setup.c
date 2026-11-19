// mybench-usb-setup: lets mybench use a myDAQ through the WinUSB driver that ships with Windows
// (winusb.inf, signed by Microsoft, "WinUsb Device"), and gives the myDAQ back afterwards. No
// certificate, no third-party driver, no reboot.
//
// The installer registers it as the service "mybench-usb" (LocalSystem). While mybench runs it
// holds a connection to the service, which takes the plugged-in myDAQs: from NI's driver (not
// while a program has NI-DAQmx loaded: NI's driver would drop that program's task) or with no
// driver at all. When mybench quits or crashes, the service gives them back, so NI MAX, ELVISmx
// and LabVIEW have them again. What it took is written down (HKLM\SOFTWARE\mybench\UsbService)
// and given back at the next start after a crash or a power cut.
//
//   status          attached myDAQs and the driver each one uses
//   take [--force]  take the attached myDAQs now (the service does this for mybench)
//   giveback        give back what was taken
//   release         give back every myDAQ on WinUSB, ours or a Zadig/libwdi one (whose driver
//                   package is deleted): the uninstaller's clean-up
//   register        install and start the service; unregister: stop it (gives back) and remove it
//   service         run as the service; serve: the same in a console (tests)
//
// Everything but status needs administrator rights (exit code 3). Exit 0 = done or nothing to do,
// 1 = failed, 2 = usage, 4 = an NI-DAQmx program is running. --vid/--pid: another device (bench).
#ifndef UNICODE
#define UNICODE
#endif
#define PSAPI_VERSION 2
#include <windows.h>
#include <psapi.h>
#include <sddl.h>
#include <stdarg.h>
#include <string.h>
#include <setupapi.h>
#include <cfgmgr32.h>
#include <devguid.h>
#include <stdio.h>
#include <wchar.h>

#ifndef DIIDFLAG_NOFINISHINSTALLUI
#define DIIDFLAG_NOFINISHINSTALLUI 0x00000002
#endif

static wchar_t g_match[64] = L"USB\\VID_3923&PID_755B";   // NI myDAQ
// winusb.sys reads this from the device's hardware key and registers the interface libusb opens.
static const wchar_t kInterfaceGuid[] = L"{91D75FF0-DBBF-46A2-8331-CC32B017ABD9}\0";
// newdev.dll's device-level calls, loaded at run time (MinGW's import library lacks them).
typedef BOOL (WINAPI *DiInstallDevice_t)(HWND, HDEVINFO, PSP_DEVINFO_DATA, PSP_DRVINFO_DATA_W, DWORD, PBOOL);
typedef BOOL (WINAPI *DiUninstallDevice_t)(HWND, HDEVINFO, PSP_DEVINFO_DATA, DWORD, PBOOL);
static FARPROC newdev(const char* name)
{
    HMODULE h = LoadLibraryExW(L"newdev.dll", NULL, LOAD_LIBRARY_SEARCH_SYSTEM32);
    return h ? GetProcAddress(h, name) : NULL;
}
enum { EXIT_OK = 0, EXIT_FAIL = 1, EXIT_USAGE = 2, EXIT_ELEVATE = 3, EXIT_BUSY = 4 };

static int prop(HDEVINFO devs, SP_DEVINFO_DATA* dev, DWORD p, wchar_t* buf, DWORD size)
{
    buf[0] = buf[1] = 0;
    return SetupDiGetDeviceRegistryPropertyW(devs, dev, p, NULL, (BYTE*)buf, size - 2 * sizeof(wchar_t), NULL);
}

static int is_mydaq(HDEVINFO devs, SP_DEVINFO_DATA* dev)
{
    wchar_t ids[1024];
    if (!prop(devs, dev, SPDRP_HARDWAREID, ids, sizeof ids)) return 0;
    for (const wchar_t* s = ids; *s; s += wcslen(s) + 1)
        if (!_wcsnicmp(s, g_match, wcslen(g_match)) && !wcsstr(s, L"&MI_")) return 1;
    return 0;
}

static void instance_id(HDEVINFO devs, SP_DEVINFO_DATA* dev, wchar_t* out, DWORD n)
{
    if (!SetupDiGetDeviceInstanceIdW(devs, dev, out, n, NULL)) wcscpy(out, L"?");
}

// Driver state of one device: service name ("" = none) and the INF it was installed from.
static void driver_of(HDEVINFO devs, SP_DEVINFO_DATA* dev, wchar_t* service, DWORD ns, wchar_t* inf, DWORD ni, ULONG* problem)
{
    ULONG status = 0;
    *problem = 0;
    if (CM_Get_DevNode_Status(&status, problem, dev->DevInst, 0) != CR_SUCCESS) *problem = 0;
    if (!(status & DN_HAS_PROBLEM)) *problem = 0;
    if (!prop(devs, dev, SPDRP_SERVICE, service, ns)) service[0] = 0;
    inf[0] = 0;
    HKEY k = SetupDiOpenDevRegKey(devs, dev, DICS_FLAG_GLOBAL, 0, DIREG_DRV, KEY_READ);
    if (k != INVALID_HANDLE_VALUE) {
        DWORD size = ni * sizeof(wchar_t) - sizeof(wchar_t), type = 0;
        if (RegQueryValueExW(k, L"InfPath", NULL, &type, (BYTE*)inf, &size) == ERROR_SUCCESS) inf[size / sizeof(wchar_t)] = 0;
        else inf[0] = 0;
        RegCloseKey(k);
    }
}

static const wchar_t* describe(const wchar_t* service, ULONG problem)
{
    if (!service[0]) return L"no driver (mybench takes it while it runs)";
    if (!_wcsicmp(service, L"WinUSB")) return problem ? L"WinUSB, not started" : L"WinUSB (mybench uses it directly)";
    if (!_wcsnicmp(service, L"nira", 4) || !_wcsnicmp(service, L"ni", 2)) return L"NI's driver (mybench takes it while it runs)";
    return L"another driver";
}

static HDEVINFO usb_devices(int present_only)
{
    return SetupDiGetClassDevsW(NULL, L"USB", NULL, DIGCF_ALLCLASSES | (present_only ? DIGCF_PRESENT : 0));
}

static int cmd_status(void)
{
    HDEVINFO devs = usb_devices(1);
    if (devs == INVALID_HANDLE_VALUE) return EXIT_FAIL;
    SP_DEVINFO_DATA dev = {sizeof dev};
    int n = 0;
    for (DWORD i = 0; SetupDiEnumDeviceInfo(devs, i, &dev); i++) {
        if (!is_mydaq(devs, &dev)) continue;
        wchar_t id[256], service[128], inf[MAX_PATH];
        ULONG problem;
        instance_id(devs, &dev, id, 256);
        driver_of(devs, &dev, service, 128, inf, MAX_PATH, &problem);
        wprintf(L"%ls\tservice=%ls\tinf=%ls\tproblem=%lu\t%ls\n", id, service[0] ? service : L"-", inf[0] ? inf : L"-", problem, describe(service, problem));
        n++;
    }
    if (!n) wprintf(L"no myDAQ attached\n");
    SetupDiDestroyDeviceInfoList(devs);
    return EXIT_OK;
}

static int fail(const wchar_t* what)
{
    DWORD e = GetLastError();
    wchar_t msg[256] = L"";
    FormatMessageW(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, NULL, e, 0, msg, 256, NULL);
    fwprintf(stderr, L"%ls failed: 0x%08lx %ls", what, e, msg);
    return (e == ERROR_ACCESS_DENIED || e == ERROR_ELEVATION_REQUIRED) ? EXIT_ELEVATE : EXIT_FAIL;
}

static int bind_winusb(HDEVINFO devs, SP_DEVINFO_DATA* dev)
{
    // 1. Device Interface GUID for winusb.sys (what a WinUSB INF's AddReg would write).
    HKEY k = SetupDiCreateDevRegKeyW(devs, dev, DICS_FLAG_GLOBAL, 0, DIREG_DEV, NULL, NULL);
    if (k == INVALID_HANDLE_VALUE) return fail(L"Opening the device's registry key");
    LONG r = RegSetValueExW(k, L"DeviceInterfaceGUIDs", 0, REG_MULTI_SZ, (const BYTE*)kInterfaceGuid, sizeof kInterfaceGuid);
    RegCloseKey(k);
    if (r != ERROR_SUCCESS) { SetLastError(r); return fail(L"Writing DeviceInterfaceGUIDs"); }

    // 2. Driver list = the inbox winusb.inf only, as a USBDevice-class driver.
    static const wchar_t kUsbDeviceClass[] = L"{88BAE032-5A81-49F0-BC3D-A4FF138216D6}";
    if (!SetupDiSetDeviceRegistryPropertyW(devs, dev, SPDRP_CLASSGUID, (const BYTE*)kUsbDeviceClass, sizeof kUsbDeviceClass))
        return fail(L"Setting the device class");
    SP_DEVINSTALL_PARAMS_W ip = {sizeof ip};
    if (!SetupDiGetDeviceInstallParamsW(devs, dev, &ip)) return fail(L"Reading install parameters");
    UINT len = GetWindowsDirectoryW(ip.DriverPath, MAX_PATH);
    if (!len || len > MAX_PATH - 20) return fail(L"GetWindowsDirectory");
    wcscat(ip.DriverPath, L"\\INF\\winusb.inf");
    ip.Flags |= DI_ENUMSINGLEINF;
    ip.FlagsEx |= DI_FLAGSEX_ALLOWEXCLUDEDDRVS;
    if (!SetupDiSetDeviceInstallParamsW(devs, dev, &ip)) return fail(L"Setting install parameters");
    if (!SetupDiBuildDriverInfoList(devs, dev, SPDIT_CLASSDRIVER)) return fail(L"Reading winusb.inf");

    SP_DRVINFO_DATA_W drv = {sizeof drv};
    int found = 0;
    for (DWORD i = 0; !found && SetupDiEnumDriverInfoW(devs, dev, SPDIT_CLASSDRIVER, i, &drv); i++) {
        BYTE buf[4096];
        SP_DRVINFO_DETAIL_DATA_W* det = (SP_DRVINFO_DETAIL_DATA_W*)buf;
        det->cbSize = sizeof *det;
        if (!SetupDiGetDriverInfoDetailW(devs, dev, &drv, det, sizeof buf, NULL) && GetLastError() != ERROR_INSUFFICIENT_BUFFER) continue;
        if (!_wcsicmp(det->HardwareID, L"USB\\MS_COMP_WINUSB")) found = 1;
    }
    if (!found) { SetLastError(ERROR_NOT_FOUND); return fail(L"Finding \"WinUsb Device\" in winusb.inf"); }
    if (!SetupDiSetSelectedDriverW(devs, dev, &drv)) return fail(L"Selecting the WinUSB driver");

    // 3. Install it on this device instance only (newdev's DiInstallDevice, as Device Manager does).
    BOOL reboot = FALSE;
    DiInstallDevice_t install = (DiInstallDevice_t)newdev("DiInstallDevice");
    if (!install || !install(NULL, devs, dev, &drv, DIIDFLAG_NOFINISHINSTALLUI, &reboot)) return fail(L"Installing WinUSB");
    if (reboot) wprintf(L"Windows asks for a restart to finish.\n");
    return EXIT_OK;
}

static void rescan(void)
{
    DEVINST root;
    if (CM_Locate_DevNodeW(&root, NULL, CM_LOCATE_DEVNODE_NORMAL) == CR_SUCCESS)
        CM_Reenumerate_DevNode(root, CM_REENUMERATE_SYNCHRONOUS);
}

static const wchar_t* serial_of(const wchar_t* instance)
{
    const wchar_t* s = wcsrchr(instance, L'\\');
    return s ? s + 1 : instance;
}

static void append(wchar_t* out, size_t n, const wchar_t* fmt, ...)
{
    size_t len = wcslen(out);
    va_list ap;
    va_start(ap, fmt);
    if (len < n) _vsnwprintf(out + len, n - len - 1, fmt, ap);
    va_end(ap);
    out[n - 1] = 0;
}

// ---- Programs using NI-DAQmx -------------------------------------------------------------------
// NI's driver lets the myDAQ go even in the middle of a task (no Plug and Play veto), so before
// taking it we look for programs of a user session (not NI's services in session 0) that have
// NI-DAQmx (nicaiu.dll) loaded: NI MAX, LabVIEW, the ELVISmx instruments, a nidaqmx script...
// Returns how many; their program names go to `names` ("NIMax.exe, LabVIEW.exe").
static int ni_programs(wchar_t* names, size_t n)
{
    names[0] = 0;
    DWORD pids[4096], bytes = 0;
    if (!K32EnumProcesses(pids, sizeof pids, &bytes)) return 0;
    int count = 0;
    for (DWORD i = 0; i < bytes / sizeof(DWORD); i++) {
        DWORD session = 0;
        if (!pids[i] || pids[i] == GetCurrentProcessId() || !ProcessIdToSessionId(pids[i], &session) || !session) continue;
        HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ, FALSE, pids[i]);
        if (!h) continue;
        HMODULE mods[1024];
        DWORD need = 0;
        // Fails now and then while the process is loading DLLs (ERROR_PARTIAL_COPY), which is
        // exactly when an NI program starts a task: retry, and if it keeps failing count the
        // program as busy for this round (mybench asks again 2 s later).
        BOOL listed = FALSE;
        for (int attempt = 0; attempt < 10 && !(listed = K32EnumProcessModulesEx(h, mods, sizeof mods, &need, LIST_MODULES_ALL)); attempt++)
            Sleep(20);
        if (!listed) {
            wchar_t path[MAX_PATH] = L"?";
            DWORD len = MAX_PATH;
            QueryFullProcessImageNameW(h, 0, path, &len);
            const wchar_t* exe = wcsrchr(path, L'\\');
            exe = exe ? exe + 1 : path;
            if (!wcsstr(names, exe)) append(names, n, L"%ls%ls", names[0] ? L", " : L"", exe);
            count++;
        } else {
            DWORD m = (need < sizeof mods ? need : sizeof mods) / sizeof(HMODULE);
            for (DWORD j = 0; j < m; j++) {
                wchar_t mod[MAX_PATH];
                if (!K32GetModuleBaseNameW(h, mods[j], mod, MAX_PATH) || _wcsicmp(mod, L"nicaiu.dll")) continue;
                wchar_t path[MAX_PATH] = L"?";
                DWORD len = MAX_PATH;
                QueryFullProcessImageNameW(h, 0, path, &len);
                const wchar_t* exe = wcsrchr(path, L'\\');
                exe = exe ? exe + 1 : path;
                if (!wcsstr(names, exe)) append(names, n, L"%ls%ls", names[0] ? L", " : L"", exe);
                count++;
                break;
            }
        }
        CloseHandle(h);
    }
    return count;
}

// ---- Lease bookkeeping (HKLM\SOFTWARE\mybench\UsbService "Leased", REG_MULTI_SZ) ----------------
// The device instances the service took; given back when the last client goes, when the service
// stops, and at service start (after a crash or a power cut).
static const wchar_t kLeaseKey[] = L"SOFTWARE\\mybench\\UsbService";

static DWORD lease_read(wchar_t* buf, DWORD chars)
{
    DWORD size = (chars - 2) * sizeof(wchar_t);
    memset(buf, 0, chars * sizeof(wchar_t));
    if (RegGetValueW(HKEY_LOCAL_MACHINE, kLeaseKey, L"Leased", RRF_RT_REG_MULTI_SZ, NULL, buf, &size) != ERROR_SUCCESS) {
        buf[0] = buf[1] = 0;
        return 0;
    }
    return size;
}

static void lease_write(const wchar_t* list)
{
    DWORD chars = 0;
    while (list[chars]) chars += (DWORD)wcslen(list + chars) + 1;
    HKEY k;
    if (RegCreateKeyExW(HKEY_LOCAL_MACHINE, kLeaseKey, 0, NULL, 0, KEY_SET_VALUE, NULL, &k, NULL) != ERROR_SUCCESS) return;
    RegSetValueExW(k, L"Leased", 0, REG_MULTI_SZ, (const BYTE*)list, (chars + 1) * sizeof(wchar_t));
    RegCloseKey(k);
}

static void lease_add(const wchar_t* id)
{
    wchar_t list[4096];
    lease_read(list, 4096);
    size_t end = 0;
    for (const wchar_t* s = list; *s; s += wcslen(s) + 1) {
        if (!_wcsicmp(s, id)) return;
        end = (s - list) + wcslen(s) + 1;
    }
    if (end + wcslen(id) + 2 >= 4096) return;
    wcscpy(list + end, id);
    list[end + wcslen(id) + 1] = 0;
    lease_write(list);
}

// ---- Take / give back -------------------------------------------------------------------------
enum { TAKE_OK, TAKE_ALREADY, TAKE_BUSY, TAKE_OTHER, TAKE_FAILED };

// Takes every attached myDAQ that has no driver or NI's driver (not one with NI-DAQmx programs
// running, unless `force`). One line per myDAQ goes to `out`: "ok|busy|other|fail SERIAL detail".
static int take_all(int force, wchar_t* out, size_t n)
{
    HDEVINFO devs = usb_devices(1);
    if (devs == INVALID_HANDLE_VALUE) return fail(L"Listing USB devices");
    SP_DEVINFO_DATA dev = {sizeof dev};
    int rc = EXIT_OK;
    for (DWORD i = 0; SetupDiEnumDeviceInfo(devs, i, &dev); i++) {
        if (!is_mydaq(devs, &dev)) continue;
        wchar_t id[256], service[128], inf[MAX_PATH];
        ULONG problem;
        instance_id(devs, &dev, id, 256);
        driver_of(devs, &dev, service, 128, inf, MAX_PATH, &problem);
        const int ni = !_wcsnicmp(service, L"ni", 2);
        if (!_wcsicmp(service, L"WinUSB")) { append(out, n, L"ok %ls already on WinUSB\n", serial_of(id)); continue; }
        if (service[0] && !ni) { append(out, n, L"other %ls %ls\n", serial_of(id), service); continue; }
        if (ni && !force) {
            wchar_t names[512];
            // Twice, 300 ms apart: a script that runs NI programs one after the other has short
            // gaps with none running. A program that starts during the ~1 s switch is still hit.
            int busy = ni_programs(names, 512);
            if (!busy) { Sleep(300); busy = ni_programs(names, 512); }
            if (busy) { append(out, n, L"busy %ls %ls\n", serial_of(id), names); rc = EXIT_BUSY; continue; }
        }
        lease_add(id);   // first: a crash between here and the end still gives it back
        if (bind_winusb(devs, &dev)) {
            append(out, n, L"fail %ls could not install WinUSB (0x%08lx)\n", serial_of(id), GetLastError());
            rc = EXIT_FAIL;
            continue;
        }
        append(out, n, L"ok %ls taken from %ls\n", serial_of(id), ni ? L"NI's driver" : L"no driver");
    }
    SetupDiDestroyDeviceInfoList(devs);
    return rc;
}

// Gives back the leased myDAQs (all = also every other myDAQ on WinUSB, and deletes Zadig/libwdi
// packages for it: the uninstaller's clean-up). Plugged in or not; the best installed driver
// (NI's, if any) takes them at the rescan.
static int give_back(int all, wchar_t* out, size_t n)
{
    wchar_t leased[4096];
    lease_read(leased, 4096);
    HDEVINFO devs = usb_devices(0);
    if (devs == INVALID_HANDLE_VALUE) return fail(L"Listing USB devices");
    SP_DEVINFO_DATA dev = {sizeof dev};
    int rc = EXIT_OK, changed = 0;
    for (DWORD i = 0; SetupDiEnumDeviceInfo(devs, i, &dev); i++) {
        if (!is_mydaq(devs, &dev)) continue;
        wchar_t id[256], service[128], inf[MAX_PATH];
        ULONG problem;
        instance_id(devs, &dev, id, 256);
        int ours = 0;
        for (const wchar_t* s = leased; *s; s += wcslen(s) + 1) ours |= !_wcsicmp(s, id);
        if (!ours && !all) continue;
        driver_of(devs, &dev, service, 128, inf, MAX_PATH, &problem);
        if (_wcsicmp(service, L"WinUSB")) continue;
        if (all && !_wcsnicmp(inf, L"oem", 3)) {
            if (SetupUninstallOEMInfW(inf, SUOI_FORCEDELETE, NULL)) append(out, n, L"deleted %ls driver package %ls\n", serial_of(id), inf);
            else fail(L"Deleting the WinUSB driver package");
        }
        BOOL reboot = FALSE;
        DiUninstallDevice_t uninstall = (DiUninstallDevice_t)newdev("DiUninstallDevice");
        if (!uninstall || !uninstall(NULL, devs, &dev, 0, &reboot)) {
            append(out, n, L"fail %ls could not remove WinUSB (0x%08lx)\n", serial_of(id), GetLastError());
            rc = EXIT_FAIL;
            continue;
        }
        changed++;
        append(out, n, L"ok %ls given back\n", serial_of(id));
    }
    SetupDiDestroyDeviceInfoList(devs);
    if (rc == EXIT_OK) lease_write(L"\0");
    if (changed) rescan();
    return rc;
}

// ---- Service ----------------------------------------------------------------------------------
// "mybench-usb" (LocalSystem, automatic delayed start). mybench connects to \\.\pipe\mybench-usb
// and keeps the connection while it runs; lines in, replies ending with "end":
//   take         take the attached myDAQs (not while an NI-DAQmx program runs)
//   take force   take them even then (the user said so; that program loses the myDAQ)
//   giveback     give the leased myDAQs back now (mybench does not take them again by itself)
//   status       one line per attached myDAQ
// When the last connection closes (mybench quits or crashes) every leased myDAQ is given back.
static const wchar_t kServiceName[] = L"mybench-usb";
static const wchar_t kPipeName[] = L"\\\\.\\pipe\\mybench-usb";
static SERVICE_STATUS_HANDLE g_status_handle;
static SERVICE_STATUS g_status;
static HANDLE g_stop;
static CRITICAL_SECTION g_lock;
static LONG g_clients;

static void set_state(DWORD state)
{
    g_status.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
    g_status.dwCurrentState = state;
    g_status.dwControlsAccepted = state == SERVICE_RUNNING ? SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN : 0;
    g_status.dwWaitHint = state == SERVICE_RUNNING || state == SERVICE_STOPPED ? 0 : 10000;
    if (g_status_handle) SetServiceStatus(g_status_handle, &g_status);
}

static void status_lines(wchar_t* out, size_t n)
{
    HDEVINFO devs = usb_devices(1);
    if (devs == INVALID_HANDLE_VALUE) return;
    SP_DEVINFO_DATA dev = {sizeof dev};
    for (DWORD i = 0; SetupDiEnumDeviceInfo(devs, i, &dev); i++) {
        if (!is_mydaq(devs, &dev)) continue;
        wchar_t id[256], service[128], inf[MAX_PATH];
        ULONG problem;
        instance_id(devs, &dev, id, 256);
        driver_of(devs, &dev, service, 128, inf, MAX_PATH, &problem);
        append(out, n, L"device %ls %ls\n", serial_of(id), service[0] ? service : L"-");
    }
    SetupDiDestroyDeviceInfoList(devs);
}

static DWORD WINAPI client_thread(void* arg)
{
    HANDLE pipe = (HANDLE)arg;
    InterlockedIncrement(&g_clients);
    char in[512];
    size_t used = 0;
    for (;;) {
        DWORD got = 0;
        if (!ReadFile(pipe, in + used, (DWORD)(sizeof in - 1 - used), &got, NULL) || !got) break;
        used += got;
        in[used] = 0;
        char* nl;
        while ((nl = strchr(in, '\n'))) {
            *nl = 0;
            if (nl > in && nl[-1] == '\r') nl[-1] = 0;
            static wchar_t reply[8192];   // replies are built under g_lock
            EnterCriticalSection(&g_lock);
            reply[0] = 0;
            if (!strcmp(in, "take")) take_all(0, reply, 8192);
            else if (!strcmp(in, "take force")) take_all(1, reply, 8192);
            else if (!strcmp(in, "giveback")) give_back(0, reply, 8192);
            else if (!strcmp(in, "status")) status_lines(reply, 8192);
            else append(reply, 8192, L"error unknown command\n");
            append(reply, 8192, L"end\n");
            char utf8[16384];
            int len = WideCharToMultiByte(CP_UTF8, 0, reply, -1, utf8, sizeof utf8, NULL, NULL);
            LeaveCriticalSection(&g_lock);
            DWORD put = 0;
            if (len > 1 && !WriteFile(pipe, utf8, (DWORD)len - 1, &put, NULL)) goto done;
            used -= (size_t)(nl + 1 - in);
            memmove(in, nl + 1, used + 1);
        }
        if (used >= sizeof in - 1) break;   // a line that long is not ours
    }
done:
    FlushFileBuffers(pipe);
    DisconnectNamedPipe(pipe);
    CloseHandle(pipe);
    if (InterlockedDecrement(&g_clients) == 0) {
        wchar_t reply[2048] = L"";
        EnterCriticalSection(&g_lock);
        if (g_clients == 0) give_back(0, reply, 2048);
        LeaveCriticalSection(&g_lock);
    }
    return 0;
}

static void serve(void)
{
    // SYSTEM and administrators: full access; interactively logged-on users: read/write.
    SECURITY_ATTRIBUTES sa = {sizeof sa, NULL, FALSE};
    ConvertStringSecurityDescriptorToSecurityDescriptorW(L"D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;GRGW;;;IU)", SDDL_REVISION_1,
                                                         &sa.lpSecurityDescriptor, NULL);
    wchar_t reply[2048] = L"";
    EnterCriticalSection(&g_lock);
    give_back(0, reply, 2048);   // leftovers of a crash or a power cut
    LeaveCriticalSection(&g_lock);
    OVERLAPPED ov = {0};
    ov.hEvent = CreateEventW(NULL, TRUE, FALSE, NULL);
    while (WaitForSingleObject(g_stop, 0) == WAIT_TIMEOUT) {
        HANDLE pipe = CreateNamedPipeW(kPipeName, PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED,
                                       PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
                                       PIPE_UNLIMITED_INSTANCES, 16384, 512, 0, &sa);
        if (pipe == INVALID_HANDLE_VALUE) { Sleep(1000); continue; }
        ResetEvent(ov.hEvent);
        BOOL connected = ConnectNamedPipe(pipe, &ov);
        DWORD e = GetLastError();
        if (!connected && e == ERROR_IO_PENDING) {
            HANDLE waits[2] = {g_stop, ov.hEvent};
            if (WaitForMultipleObjects(2, waits, FALSE, INFINITE) == WAIT_OBJECT_0) { CancelIo(pipe); CloseHandle(pipe); break; }
            DWORD dummy;
            connected = GetOverlappedResult(pipe, &ov, &dummy, FALSE);
        } else if (!connected && e == ERROR_PIPE_CONNECTED) {
            connected = TRUE;
        }
        if (!connected) { CloseHandle(pipe); continue; }
        // Client threads use blocking I/O on an overlapped handle: fine with one outstanding call each.
        HANDLE t = CreateThread(NULL, 0, client_thread, pipe, 0, NULL);
        if (t) CloseHandle(t); else CloseHandle(pipe);
    }
    CloseHandle(ov.hEvent);
    EnterCriticalSection(&g_lock);
    give_back(0, reply, 2048);
    LeaveCriticalSection(&g_lock);
}

static DWORD WINAPI control(DWORD code, DWORD type, void* data, void* ctx)
{
    (void)type; (void)data; (void)ctx;
    if (code == SERVICE_CONTROL_STOP || code == SERVICE_CONTROL_SHUTDOWN) {
        set_state(SERVICE_STOP_PENDING);
        SetEvent(g_stop);
    }
    return NO_ERROR;
}

static void WINAPI service_main(DWORD argc, wchar_t** argv)
{
    (void)argc; (void)argv;
    g_status_handle = RegisterServiceCtrlHandlerExW(kServiceName, control, NULL);
    set_state(SERVICE_RUNNING);
    serve();
    set_state(SERVICE_STOPPED);
}

static int cmd_register(void)
{
    wchar_t exe[MAX_PATH], cmd[MAX_PATH + 32];
    GetModuleFileNameW(NULL, exe, MAX_PATH);
    swprintf(cmd, MAX_PATH + 32, L"\"%ls\" service", exe);
    SC_HANDLE scm = OpenSCManagerW(NULL, NULL, SC_MANAGER_ALL_ACCESS);
    if (!scm) return fail(L"Opening the service manager");
    SC_HANDLE s = CreateServiceW(scm, kServiceName, L"mybench USB access", SERVICE_ALL_ACCESS, SERVICE_WIN32_OWN_PROCESS,
                                 SERVICE_AUTO_START, SERVICE_ERROR_NORMAL, cmd, NULL, NULL, NULL, NULL, NULL);
    if (!s && GetLastError() == ERROR_SERVICE_EXISTS) {
        s = OpenServiceW(scm, kServiceName, SERVICE_ALL_ACCESS);
        if (s) ChangeServiceConfigW(s, SERVICE_NO_CHANGE, SERVICE_AUTO_START, SERVICE_NO_CHANGE, cmd, NULL, NULL, NULL, NULL, NULL, NULL);
    }
    if (!s) { int r = fail(L"Registering the service"); CloseServiceHandle(scm); return r; }
    SERVICE_DESCRIPTIONW desc = {L"Lets mybench use a plugged-in NI myDAQ while mybench runs, and gives it back to NI's software when mybench closes."};
    ChangeServiceConfig2W(s, SERVICE_CONFIG_DESCRIPTION, &desc);
    SERVICE_DELAYED_AUTO_START_INFO delayed = {TRUE};
    ChangeServiceConfig2W(s, SERVICE_CONFIG_DELAYED_AUTO_START_INFO, &delayed);
    SC_ACTION restart[2] = {{SC_ACTION_RESTART, 5000}, {SC_ACTION_RESTART, 30000}};
    SERVICE_FAILURE_ACTIONSW fa = {86400, NULL, NULL, 2, restart};
    ChangeServiceConfig2W(s, SERVICE_CONFIG_FAILURE_ACTIONS, &fa);
    int rc = EXIT_OK;
    if (!StartServiceW(s, 0, NULL) && GetLastError() != ERROR_SERVICE_ALREADY_RUNNING) rc = fail(L"Starting the service");
    else wprintf(L"service %ls running\n", kServiceName);
    CloseServiceHandle(s);
    CloseServiceHandle(scm);
    return rc;
}

static int cmd_unregister(void)
{
    SC_HANDLE scm = OpenSCManagerW(NULL, NULL, SC_MANAGER_ALL_ACCESS);
    if (!scm) return fail(L"Opening the service manager");
    SC_HANDLE s = OpenServiceW(scm, kServiceName, SERVICE_ALL_ACCESS);
    if (s) {
        SERVICE_STATUS st;
        if (ControlService(s, SERVICE_CONTROL_STOP, &st))
            for (int i = 0; i < 100 && QueryServiceStatus(s, &st) && st.dwCurrentState != SERVICE_STOPPED; i++) Sleep(100);
        DeleteService(s);
        CloseServiceHandle(s);
        wprintf(L"service %ls removed\n", kServiceName);
    }
    CloseServiceHandle(scm);
    return EXIT_OK;
}

static int print_result(int rc, const wchar_t* out)
{
    fputws(out[0] ? out : L"no myDAQ to change\n", stdout);
    return rc;
}

int wmain(int argc, wchar_t** argv)
{
    const wchar_t* cmd = NULL;
    int force = 0;
    unsigned vid = 0, pid = 0;
    for (int i = 1; i < argc; i++) {
        if (!wcscmp(argv[i], L"--vid") && i + 1 < argc) vid = wcstoul(argv[++i], NULL, 16);
        else if (!wcscmp(argv[i], L"--pid") && i + 1 < argc) pid = wcstoul(argv[++i], NULL, 16);
        else if (!wcscmp(argv[i], L"--force")) force = 1;
        else if (!cmd) cmd = argv[i];
    }
    if (vid || pid) swprintf(g_match, 64, L"USB\\VID_%04X&PID_%04X", vid, pid);
    InitializeCriticalSection(&g_lock);
    static wchar_t out[8192];
    if (cmd && !wcscmp(cmd, L"status")) return cmd_status();
    if (cmd && !wcscmp(cmd, L"take")) return print_result(take_all(force, out, 8192), out);
    if (cmd && !wcscmp(cmd, L"giveback")) return print_result(give_back(0, out, 8192), out);
    if (cmd && !wcscmp(cmd, L"release")) return print_result(give_back(1, out, 8192), out);
    if (cmd && !wcscmp(cmd, L"register")) return cmd_register();
    if (cmd && !wcscmp(cmd, L"unregister")) return cmd_unregister();
    if (cmd && (!wcscmp(cmd, L"service") || !wcscmp(cmd, L"serve"))) {
        g_stop = CreateEventW(NULL, TRUE, FALSE, NULL);
        if (!wcscmp(cmd, L"serve")) { serve(); return EXIT_OK; }   // console run, for tests
        SERVICE_TABLE_ENTRYW table[] = {{(wchar_t*)kServiceName, service_main}, {NULL, NULL}};
        return StartServiceCtrlDispatcherW(table) ? EXIT_OK : fail(L"Starting as a service");
    }
    fwprintf(stderr, L"usage: mybench-usb-setup status|take [--force]|giveback|release|register|unregister|service\n");
    return EXIT_USAGE;
}
