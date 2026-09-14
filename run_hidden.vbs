' run-hidden.vbs — запускает указанный .ps1 полностью без окна
' Использование: wscript run-hidden.vbs daemon.ps1
Dim shell, scriptDir, ps1
Set shell = CreateObject("WScript.Shell")
scriptDir = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))

If WScript.Arguments.Count = 0 Then
    ps1 = scriptDir & "collector.ps1"
Else
    ps1 = scriptDir & WScript.Arguments(0)
End If

shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & ps1 & """", 0, False