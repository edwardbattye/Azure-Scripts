Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Import-Module PowerShellGet
New-Item -Path 'C:\Program Files'-Name 'WindowsPowershellScripts' -ItemType "directory" -Force
$Path = 'C:\Program Files'
$repo = @{
    Name = 'MyRepository'
    SourceLocation = $Path
    PublishLocation = $Path
    InstallationPolicy = 'Trusted'
}
Register-PSRepository @repo

Install-Script -Name Get-WindowsAutoPilotInfo
Get-WindowsAutoPilotInfo.ps1 -Online -AddToGroup "Group_Name" -Assign