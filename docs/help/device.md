# Device

The myDAQ and the built-in demo device. No NI software is needed: mybench has its own USB driver, on macOS, Windows and Linux.

## Demo device

Without a myDAQ, **Use Demo** (Overview, or **Device** menu) runs the simulated myDAQ: every instrument works, AO 0 is wired to AI 0 and AI 1.

## Not available

A myDAQ that is plugged in but cannot be opened is listed in the **Device** menu and on the Overview as **Not available**, with the cause. **Rescan** tries again; mybench also retries on its own.

| Label | Meaning | Fix |
|---|---|---|
| **NI driver** | Windows: NI's driver owns the myDAQ, and only one driver can | Bind **WinUSB** to the myDAQ (below), re-plug |
| **No permission** | Linux: the user may not open the USB device | Install the udev rule (below), re-plug |
| **In use** | Another mybench window or program has the myDAQ open | Close it, **Rescan** |
| **Open failed** | The myDAQ did not answer (just plugged in, hub, cable) | Re-plug, try another port |

## Windows: NI driver

mybench needs no NI software (ELVISmx, NI-DAQmx) and does not use it. If it is installed, NI's kernel driver owns the myDAQ and mybench cannot open it. Replace it with WinUSB for this one USB device (`3923:755b`):

1. Close NI MAX and ELVISmx.
2. Download Zadig from <https://zadig.akeo.ie>.
3. Start Zadig, choose **Options → List All Devices**, select **NI myDAQ** (USB ID `3923` `755B`).
4. Choose **WinUSB**, click **Replace Driver**.
5. Re-plug the myDAQ.

NI's software no longer sees the myDAQ afterwards. Going back to NI's driver is in the install guide.

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
