; Uninstall: stop and remove the mybench-usb service (it gives back what it borrowed), then give
; every myDAQ still on WinUSB (an old Zadig binding too) back to Windows' best driver, NI's when NI
; software is installed; plugged in or not. Runs before the files are deleted.
DetailPrint "myDAQ: removing the mybench USB service..."
nsExec::ExecToLog '"$INSTDIR\bin\mybench-usb-setup.exe" unregister'
Pop $0
nsExec::ExecToLog '"$INSTDIR\bin\mybench-usb-setup.exe" release'
Pop $0
