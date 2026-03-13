Write-Host "Scanning installed software..." -ForegroundColor Cyan

# Create output folder
$OutputFolder = "$env:USERPROFILE\Desktop\Software_Scan"
New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null

# Scan 64-bit programs (system-wide)
$apps64 = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*

# Scan 32-bit programs (system-wide)
$apps32 = Get-ItemProperty HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*

# Scan per-user installed programs
$appsUser = Get-ItemProperty HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue

# Combine registry results
$apps = $apps64 + $apps32 + $appsUser

# Select useful fields from registry apps
$registryApps = $apps |
    Where-Object {$_.DisplayName} |
    Select-Object @{N="Name";E={$_.DisplayName}},
                  @{N="Version";E={$_.DisplayVersion}},
                  @{N="Publisher";E={$_.Publisher}},
                  @{N="InstallDate";E={$_.InstallDate}},
                  @{N="Source";E={"Registry"}} |
    Sort-Object Name

# Scan Microsoft Store apps
$storeApps = Get-AppxPackage | Select-Object @{N="Name";E={$_.Name}},
                                              @{N="Version";E={$_.Version}},
                                              @{N="Publisher";E={$_.Publisher}},
                                              @{N="InstallDate";E={"N/A"}},
                                              @{N="Source";E={"Microsoft Store"}} |
    Sort-Object Name

# Combine all results
$allApps = $registryApps + $storeApps

$allApps | Export-Csv "$OutputFolder\installed_programs.csv" -NoTypeInformation

Write-Host "Scan complete." -ForegroundColor Green
Write-Host "Total programs found: $($allApps.Count)"
Write-Host "Results saved to: $OutputFolder\installed_programs.csv"