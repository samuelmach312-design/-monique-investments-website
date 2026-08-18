Option Explicit

Dim WSHShell, shellApp, strURL, strArgs
Set WSHShell=CreateObject("WScript.Shell")

strURL="https://localhost:8443/pem"
strArgs= "url.dll,FileProtocolHandler " & strURL

Set shellApp = WScript.CreateObject("Shell.Application")
shellApp.ShellExecute "rundll32.exe", strArgs, "", "open", 0

