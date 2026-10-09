Option Explicit
Dim shell, fso, action, control, cmd, folder, wmi, processes, proc
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
If WScript.Arguments.Count <> 1 Then
  MsgBox "Use START MyGitea2.bat or STOP MyGitea2.bat.", 48, "MyGitea2"
  WScript.Quit 1
End If
action = LCase(WScript.Arguments(0))
If action <> "start" And action <> "stop" Then WScript.Quit 1
folder = fso.GetParentFolderName(WScript.ScriptFullName)
control = fso.BuildPath(folder, "MyGitea-Control.ps1")
If Not fso.FileExists(control) Then
  MsgBox "Missing launcher: " & control, 16, "MyGitea2"
  WScript.Quit 1
End If
If action = "start" Then
  Set wmi = GetObject("winmgmts:\\.\root\cimv2")
  Set processes = wmi.ExecQuery("SELECT CommandLine FROM Win32_Process WHERE Name = 'powershell.exe'")
  For Each proc In processes
    If Not IsNull(proc.CommandLine) Then
      If InStr(1, proc.CommandLine, control, vbTextCompare) > 0 Then
        MsgBox "MyGitea2 launcher is already running. Use its existing app window.", 64, "MyGitea2"
        WScript.Quit 0
      End If
    End If
  Next
End If
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & control & Chr(34) & " -Action " & action
shell.Run cmd, 0, False
