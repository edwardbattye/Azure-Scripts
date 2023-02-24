$name = $env:COMPUTERNAME
$name | Out-File -Filepath C:\name.txt -NoClobber 
$url = "ppkg_download_url_here"
Invoke-WebRequest -Uri $url -OutFile "C:\Enroll Thin Laptop.ppkg"
Install-ProvisioningPackage -PackagePath "C:\Enroll Thin Laptop.ppkg" -QuietInstall -Force
Shutdown.exe /a
Start-Sleep -Seconds 30
##Rename-Computer -Newname $name -Force
$serial = wmic bios get SerialNumber
$text = "$name has enrolled to Azure. Serial number:$serial "
$Body = @{
    
    "Text" = "$name has enrolled to Azure. $serial "
}
$json = ConvertTo-Json $Body


Invoke-RestMethod -Method post -ContentType 'Application/Json' -Body $json -Uri "Webhook_goes_here"

##rename computer scheduled task
$action = New-ScheduledTaskAction -Execute "Powershell.exe" -Argument '$name = Get-Content -Path C:\name.txt
If($env:COMPUTERNAME -ne $name) {
    Rename-Computer -NewName $name
}'

$trigger = New-JobTrigger -AtStartup -RandomDelay 00:00:30

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$task = New-ScheduledTask -Action $action -Trigger $trigger -Settings $settings
Register-ScheduledTask Rename_PC -InputObject $task -User "System"



