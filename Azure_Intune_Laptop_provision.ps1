#This script is used to provision a Levono Laptop in Intune. The script checks if the device has already been registered in Intune and deletes if it has, otherwise errors will occur during provisioning. 

#Check if the laptop is running on battery, if it wait until mains power to continue
Param($computer = “localhost”)
Function Test-IsOnBattery
{
Param(
[string]$computer
)
[BOOL](Get-WmiObject -Class BatteryStatus -Namespace root\wmi `
-ComputerName $computer).PowerOnLine
}
$AcCheck = test-isOnBattery -computer $computer
Do {

If(!$AcCheck){
    Write-Host "Please plug in power to continue"
    Start-Sleep -Seconds 5
    $AcCheck = test-isOnBattery -computer $computer
    } 
}Until($AcCheck)

Powercfg /Change standby-timeout-ac 0

#Install NuGet and set PSGallery as trusted so we can install Modules without asking the user

Write-Host "Installing NuGet"
$nuget= Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted


#Check for the asset tag in the BIOS, if it isn't in the BIOS then set it
$AssetTag = (Get-WmiObject -Class Win32_SystemEnclosure | Select-Object SMBiosAssetTag).SMBiosAssetTag
If((!$AssetTag) -or ($AssetTag -Like "No Asset Information")){
    Write-Host "Enter Asset"
    $computername = Read-Host
    $name = 'LAP'+$computername
    $asset_url = 'WinAIA64_download_link_here'
    Write-Host "Downloading WinAIA64 so I can set the asset tag in the bios..."
    Invoke-WebRequest -Uri $asset_url -OutFile "C:\WinAIA64.exe"
    Write-Host "Setting the asset tag in the bios"
    C:\WinAIA64.exe -silent -set "USERASSETDATA.ASSET_NUMBER=$name"
}
#Check TPM status and exit if not ready

$tpmtoolOutput = @(tpmtool getdeviceinformation)

$output = @{}

foreach ($line in $tpmtoolOutput)
{
   if (!$line) { continue }

   $line = $line -replace "^-", ""

   $kv = $line.Split(":")

   if ($kv.Count -ne 2) { continue }

   $kv[1] = $kv[1] -replace "^\s+", ""

   if ($kv[0] -like "*spec version*" -or $kv[0] -like "*errata date*") { continue }

   $kv[0] = $kv[0] -replace "\s+", ""

   $output.Add($kv[0], "`"$($kv[1])`"")
}
$tpm = $($output.Keys.ForEach({"$_=$($output.$_)"}) -join ' ')
If($tpm -NotLike '*ReadyForAttestation="True"*'){
    Write-Host "Attestation status is not ready, make sure TPM is enabled, check system time, make sure bios firmware is up-to-date"
    Exit
    }
Else{
    Write-Host "Attestation is ready"
    }
If($tpm -NotLike '*ReadyForStorage="True"*'){
    Write-Host "Storage is not ready, make sure TPM is enabled, check system time, make sure bios firmware is up-to-date"
    Exit
    }
Else{
    Write-Host "Storage status is ready"
    }

#Add new repo to PATH to avoid prompting the user on creation of the repo
Import-Module PowerShellGet
$Path = 'C:\Program Files\WindowsPowerShell\Scripts\'
$OldPath = (Get-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name PATH).path
$NewPath = “$OldPath;$Path”
If($OldPath -NotLike "*$Path*"){
    Set-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name    PATH -Value $NewPath
}
$RepoCheck = Get-PSRepository -Name "MyRepository" -erroraction 'silentlycontinue'
#Check for the repo, if it doesn't exist then create it
If(!$RepoCheck){
    $Repo = @{
        Name = 'MyRepository'
        SourceLocation = $Path
        PublishLocation = $Path
        InstallationPolicy = 'Trusted'
    }
    Register-PSRepository @Repo
}
$ENV:PATH="$ENV:PATH;C:\Program Files\WindowsPowerShell\Scripts\"
Set-PSRepository -Name "MyRepository" -InstallationPolicy Trusted
Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted

#Check if the AutoPilot script is already installed, if it isn't then install it and run it
Write-Host "Starting the Azure Auto Pilot Enrollement"
$ScriptPathCheck = Test-Path -Path $Path/Get-WindowsAutoPilotInfo.ps1

If(!$ScriptPathCheck){
    Install-Script Get-WindowsAutoPilotInfo
}

Get-WindowsAutoPilotInfo -Online -AddToGroup "Group_Name_Here" -Assign

#Get the serial number of device

$Serialnumber = (Get-WmiObject win32_bios).Serialnumber

#Install and import the graph intune module

Install-Module Microsoft.Graph.Intune
Import-Module Microsoft.Graph.Intune -ErrorAction Stop
Install-Module AzureAD
Import-Module AzureAD -ErrorAction Stop

Write-host "Success" -ForegroundColor Green 
Write-Host "Authenticating with MS Graph and Azure AD..." -NoNewline

#Connect to MSGraph and Azure AD

$intuneId = Connect-MSGraph -ErrorAction Stop
$aadId = Connect-AzureAD -AccountId $intuneId.UPN -ErrorAction Stop
Write-host "Success" -ForegroundColor Green
Write-host "$($Serialnumber.ToUpper())" -ForegroundColor Yellow
Write-Host "===============" -ForegroundColor Yellow
Write-host "Retrieving " -NoNewline
Write-host "Intune " -ForegroundColor Yellow -NoNewline
Write-host "managed device record/s..." -NoNewline
$IntuneDevice = Get-IntuneManagedDevice -Filter "Serialnumber eq '$Serialnumber'" -ErrorAction Stop

#If device returned by InTune then delete it

If ($IntuneDevice){
    Write-host "   Deleting DeviceName: $($IntuneDevice.deviceName)  |  Id: $($IntuneDevice.Id)  |  AzureADDeviceId: $($IntuneDevice.azureADDeviceId)  |  SerialNumber: $($IntuneDevice.serialNumber) ..." -NoNewline
    Remove-IntuneManagedDevice -managedDeviceId $IntuneDevice.Id -Verbose -ErrorAction Stop
    Write-host "Success" -ForegroundColor Green
    Write-Host "Device deleted from InTune. Reinstall with a bootable USB stick"
}
Else{
    Write-Host "Device not found in InTune"
    Write-Host "Script complete, ready for factory reset"
    systemreset -Factoryreset
}
