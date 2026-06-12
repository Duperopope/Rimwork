' Invisible launcher for the scheduled task: pwsh launched by Task Scheduler
' flashes a console window even with -WindowStyle Hidden; WScript.Shell.Run
' with window mode 0 does not.
CreateObject("WScript.Shell").Run """pwsh.exe"" -NoProfile -File ""g:\Rimwork\scripts\startup_all.ps1""", 0, False
