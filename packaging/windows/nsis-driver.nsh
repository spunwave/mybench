; myDAQ step of the mybench installer (packaging/CMakeLists.txt).
; Registers and starts the service "mybench-usb" (mybench-usb-setup.exe service, LocalSystem). It
; lends mybench the plugged-in myDAQ while mybench runs, through Windows' own WinUSB (winusb.inf,
; signed by Microsoft; no certificate, no third-party driver, no reboot), and gives it back to NI's
; driver when mybench closes. Nothing changes on the myDAQ at install time. Never fails the install.
DetailPrint "myDAQ: starting the mybench USB service..."
nsExec::ExecToLog '"$INSTDIR\bin\mybench-usb-setup.exe" register'
Pop $0
DetailPrint "mybench USB service: $0"
