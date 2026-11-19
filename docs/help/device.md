# Device

The myDAQ and the built-in demo device. No NI software is needed: mybench has its own USB driver, on macOS, Windows and Linux. On Windows it borrows the myDAQ while mybench runs and gives it back to NI's software when mybench closes.

## Demo device

Without a myDAQ, **Use Demo** (Overview, or **Device** menu) runs the simulated myDAQ: every instrument works, AO 0 is wired to AI 0 and AI 1.

## Not available

A myDAQ that is plugged in but cannot be opened is listed in the **Device** menu and on the Overview as **Not available**, with the cause. **Rescan** tries again; mybench also retries on its own.

| Label | Meaning | Fix |
|---|---|---|
| **With NI software** | Windows: an NI program (NI MAX, LabVIEW, ELVISmx) is using the myDAQ | Close it, or **Use in mybench** (below) |
| **Needs setup** | Windows: the mybench USB service is missing | Reinstall mybench, or **Set Up myDAQ** |
| **Driver** | Windows: a driver mybench cannot use owns the myDAQ | Below |
| **No permission** | Linux: the user may not open the USB device | Install the udev rule (below), re-plug |
| **In use** | Another mybench window or program has the myDAQ open | Close it, **Rescan** |
| **Open failed** | The myDAQ did not answer (just plugged in, hub, cable) | Re-plug, try another port |

## Windows

Nothing to do. Windows lets one driver at a time use the myDAQ, so mybench borrows it:

- While mybench runs, the myDAQ is mybench's (through Windows' own USB driver, WinUSB). When mybench closes, NI MAX, ELVISmx and LabVIEW get it back by themselves.
- If an NI program is using the myDAQ when mybench starts, the Overview shows **With NI software** with the program's name. mybench takes the myDAQ as soon as that program is closed. **Use in mybench** takes it at once, and that program loses the myDAQ.
- **Give to NI Software** (Overview) hands the myDAQ to NI's software while mybench keeps running. **Use in mybench** takes it back.

**Driver** means another program's driver owns the myDAQ, or the mybench USB service is not running (reinstall mybench). For another driver: in Device Manager, choose **Uninstall device** for the myDAQ, tick **Attempt to remove the driver**, and re-plug it.

## Linux: permission

Install the udev rule once (the `.deb` and `.rpm` do it), then re-plug the myDAQ:

```
sudo cp 60-mybench-mydaq.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger
```

The rule is `packaging/linux/60-mybench-mydaq.rules` in the repository.

## macOS

Nothing to install. **In use** means another program has the myDAQ open: close it, then **Rescan**.

## Unplugging

Running instruments stop with **Device disconnected** and their data stays on screen. Plug the myDAQ in again: it is selected again on its own, then start the instrument.
