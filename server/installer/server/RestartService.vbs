Option Explicit

' ------ SCRIPT CONFIGURATION ------

Dim WshShell
Set WshShell = WScript.CreateObject("WScript.Shell")

If WScript.Arguments.Count = 1 Then
	Dim strSvcName : strSvcName = WScript.Arguments.Item(0)
Else
	Wscript.echo "USAGE: cscript //nologo RestartService.vbs [ServiceName]"
	WScript.Quit 1
End If

If Len(strSvcName) = 0 Then
	WshShell.LogEvent 1, "Invalid service name provided"
	WScript.Quit 2
End If

If InStr(strSvcName, "'") <> 0 Then
	WshShell.LogEvent 1, "Invalid service name provided: " & strSvcName
	WScript.Quit 2
End If

Dim strStopServiceList : strStopServiceList = ""

' ------ END CONFIGURATION ---------
Dim objWMI : set objWMI = GetObject("winmgmts:\\.\root\cimv2")
Dim objService: set objService = objWMI.Get("Win32_Service.Name='" & strSvcName & "'")
RecursiveServiceStop objService
If strStopServiceList = "" Then
	strStopServiceList = strSvcName & ","
End If
RecursiveServiceStart objService

Function RecursiveServiceStop(objSvc)
	Dim colServices : set colServices = objWMI.ExecQuery("Associators of " & "{Win32_Service.Name='" & objSvc.Name & "'} Where " & "AssocClass=Win32_DependentService Role=Antecedent")
	Dim objS
	for each objS in colServices
		RecursiveServiceStop objS
	next

	If StrComp(objSvc.State, "Running") = 0 Then
		Dim intRC : intRC = objSvc.StopService
		Dim cnt : cnt = 1
		DO
			If StrComp(objSvc.State,"Stopped") = 0 Then
				Exit Do
			End If

			' Give the service 300 * 200 milli seconds to stop
			WScript.Sleep 300

			cnt = cnt + 1
		LOOP WHILE (cnt < 201)

		If intRC > 0 Then
			WshShell.LogEvent 1, "Error stopping service (from pem-server installer): " & objSvc.Name
			WScript.Quit 3
		Else
			strStopServiceList = strStopServiceList & objSvc.Name & ","
			WshShell.LogEvent 4, "Successfully stopped service (from pem-server installer): " & objSvc.Name
		End If
	End If
End Function

Function RecursiveServiceStart(objSvc)
	Dim retTest
	retTest = FindStoppedService(objSvc)
	if retTest = 1 then
		Dim intRC : intRC = objSvc.StartService
		Dim cnt : cnt = 1
		DO
			If StrComp(objSvc.State,"Running") = 0 Then
				Exit Do
			End If

			' Give the service 300 * 200 milli seconds to stop
			WScript.Sleep 300

			cnt = cnt + 1
		LOOP WHILE (cnt < 201)
		if intRC > 0 then
			WshShell.LogEvent 1, "Error starting service (from pem-server installer): " & objSvc.Name
			WScript.Quit 3
		else
			WshShell.LogEvent 4, "Successfully started service (from pem-server installer): " & objSvc.Name
		end if
	end if

	Dim colServices : set colServices = objWMI.ExecQuery("Associators of " & "{Win32_Service.Name='" & objSvc.Name & "'} Where " & "AssocClass=Win32_DependentService Role=Antecedent" )
	Dim objS
	for each objS in colServices
		RecursiveServiceStart objS
	next
End Function

Function FindStoppedService(objSvc)

	Dim retVal
	Dim a
	Dim x
	a = Split(strStopServiceList,",")

	For Each x In a
		Dim t
		t = StrComp(objSvc.Name, x)
		If t = 0 Then
			retVal = 1
			FindStoppedService = retVal
			Exit For
		Else
			retVal = 0
			FindStoppedService = retVal
		End If
	Next
End Function
