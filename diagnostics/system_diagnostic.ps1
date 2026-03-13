#Requires -RunAsAdministrator

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   System Diagnostic Tool v1.0" -ForegroundColor Cyan
Write-Host "   For Computer Repair Technicians" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Create output folder with timestamp so each scan is preserved
$Timestamp    = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$OutputFolder = "$env:USERPROFILE\Desktop\System_Scan\$Timestamp"
New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
Write-Host "Output folder: $OutputFolder" -ForegroundColor Green
Write-Host ""

# ============================================================
# 1. INSTALLED PROGRAMS (Registry)
# ============================================================
Write-Host "[1/8] Scanning installed programs..." -ForegroundColor Yellow

try {
    $apps64   = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"           -ErrorAction SilentlyContinue
    $apps32   = Get-ItemProperty "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue
    $appsUser = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"            -ErrorAction SilentlyContinue

    $registryApps = ($apps64 + $apps32 + $appsUser) |
        Where-Object { $_.DisplayName } |
        Select-Object @{N="Name";E={$_.DisplayName}},
                      @{N="Version";E={$_.DisplayVersion}},
                      @{N="Publisher";E={$_.Publisher}},
                      @{N="InstallDate";E={$_.InstallDate}},
                      @{N="Source";E={"Registry"}} |
        Sort-Object Name -Unique

    $registryApps | Export-Csv "$OutputFolder\01_Installed_Programs.csv" -NoTypeInformation
    Write-Host "   Found $($registryApps.Count) registry programs." -ForegroundColor Green
} catch {
    Write-Host "   ERROR scanning registry programs: $_" -ForegroundColor Red
}

# ============================================================
# 2. MICROSOFT STORE APPS
# ============================================================
Write-Host "[2/8] Scanning Microsoft Store apps..." -ForegroundColor Yellow

try {
    $storeApps = Get-AppxPackage -AllUsers -ErrorAction Stop |
        Select-Object @{N="Name";E={$_.Name}},
                      @{N="Version";E={$_.Version}},
                      @{N="Publisher";E={$_.Publisher}},
                      @{N="PackageFullName";E={$_.PackageFullName}},
                      @{N="InstallLocation";E={$_.InstallLocation}} |
        Sort-Object Name -Unique

    $storeApps | Export-Csv "$OutputFolder\02_Store_Apps.csv" -NoTypeInformation
    Write-Host "   Found $($storeApps.Count) Store apps." -ForegroundColor Green
} catch {
    Write-Host "   ERROR scanning Store apps: $_" -ForegroundColor Red
}

# ============================================================
# 3. STARTUP PROGRAMS
# ============================================================
Write-Host "[3/8] Scanning startup programs..." -ForegroundColor Yellow

try {
    $wmiStartup = Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue |
        Select-Object @{N="Name";E={$_.Name}},
                      @{N="Command";E={$_.Command}},
                      @{N="Location";E={$_.Location}},
                      @{N="User";E={$_.User}}

    $startupFolders = @(
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
        "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
    )

    $folderStartup = foreach ($folder in $startupFolders) {
        if (Test-Path $folder) {
            Get-ChildItem $folder -ErrorAction SilentlyContinue | ForEach-Object {
                [PSCustomObject]@{
                    Name     = $_.Name
                    Command  = $_.FullName
                    Location = $folder
                    User     = if ($folder -like "*APPDATA*") { $env:USERNAME } else { "All Users" }
                }
            }
        }
    }

    $allStartup = ($wmiStartup + $folderStartup) | Sort-Object Name -Unique
    $allStartup | Export-Csv "$OutputFolder\03_Startup_Programs.csv" -NoTypeInformation
    Write-Host "   Found $($allStartup.Count) startup entries." -ForegroundColor Green
} catch {
    Write-Host "   ERROR scanning startup programs: $_" -ForegroundColor Red
}

# ============================================================
# 4. SERVICES
# ============================================================
Write-Host "[4/8] Scanning services..." -ForegroundColor Yellow

try {
    $services = Get-Service -ErrorAction Stop |
        Select-Object Name, DisplayName, Status, StartType |
        Sort-Object Status, DisplayName

    $services | Export-Csv "$OutputFolder\04_Services.csv" -NoTypeInformation
    $runningCount = ($services | Where-Object { $_.Status -eq "Running" }).Count
    Write-Host "   Found $($services.Count) services ($runningCount running)." -ForegroundColor Green
} catch {
    Write-Host "   ERROR scanning services: $_" -ForegroundColor Red
}

# ============================================================
# 5. SCHEDULED TASKS
# ============================================================
Write-Host "[5/8] Scanning scheduled tasks..." -ForegroundColor Yellow

try {
    $tasks = Get-ScheduledTask -ErrorAction Stop |
        Select-Object TaskName,
                      TaskPath,
                      State,
                      @{N="RunAsUser";E={$_.Principal.UserId}},
                      @{N="Description";E={$_.Description}} |
        Sort-Object TaskPath, TaskName

    $tasks | Export-Csv "$OutputFolder\05_Scheduled_Tasks.csv" -NoTypeInformation
    Write-Host "   Found $($tasks.Count) scheduled tasks." -ForegroundColor Green
} catch {
    Write-Host "   ERROR scanning scheduled tasks: $_" -ForegroundColor Red
}

# ============================================================
# 6. HARDWARE INFORMATION
# ============================================================
Write-Host "[6/8] Scanning hardware..." -ForegroundColor Yellow

try {
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue |
        Select-Object @{N="Component";E={"CPU"}},
                      @{N="Name";E={$_.Name}},
                      @{N="Detail";E={"Cores: $($_.NumberOfCores) | Logical: $($_.NumberOfLogicalProcessors) | Max Speed: $($_.MaxClockSpeed) MHz"}}

    $ramModules = Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue
    $totalRAM   = [math]::Round(($ramModules | Measure-Object Capacity -Sum).Sum / 1GB, 2)
    $ram = $ramModules | Select-Object @{N="Component";E={"RAM"}},
                                       @{N="Name";E={$_.PartNumber.Trim()}},
                                       @{N="Detail";E={"Capacity: $([math]::Round($_.Capacity/1GB,2)) GB | Speed: $($_.Speed) MHz | Slot: $($_.DeviceLocator)"}}

    $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
        Select-Object @{N="Component";E={"GPU"}},
                      @{N="Name";E={$_.Name}},
                      @{N="Detail";E={"VRAM: $([math]::Round($_.AdapterRAM/1GB,2)) GB | Driver: $($_.DriverVersion) | Resolution: $($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution)"}}

    $mobo = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue |
        Select-Object @{N="Component";E={"Motherboard"}},
                      @{N="Name";E={"$($_.Manufacturer) $($_.Product)"}},
                      @{N="Detail";E={"Serial: $($_.SerialNumber) | Version: $($_.Version)"}}

    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue |
        Select-Object @{N="Component";E={"BIOS"}},
                      @{N="Name";E={$_.Name}},
                      @{N="Detail";E={"Manufacturer: $($_.Manufacturer) | Version: $($_.SMBIOSBIOSVersion) | Release: $($_.ReleaseDate)"}}

    $hardware = @($cpu) + @($ram) + @($gpu) + @($mobo) + @($bios)
    $hardware | Export-Csv "$OutputFolder\06_Hardware_Info.csv" -NoTypeInformation
    Write-Host "   Hardware collected. Total RAM: $totalRAM GB." -ForegroundColor Green
} catch {
    Write-Host "   ERROR scanning hardware: $_" -ForegroundColor Red
}

# ============================================================
# 7. DISK HEALTH
# ============================================================
Write-Host "[7/8] Scanning disk health..." -ForegroundColor Yellow

try {
    # Logical drives (size, free space, filesystem)
    $logicalDisks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue |
        Select-Object DeviceID,
                      @{N="Label";E={$_.VolumeName}},
                      @{N="FileSystem";E={$_.FileSystem}},
                      @{N="SizeGB";E={[math]::Round($_.Size/1GB,2)}},
                      @{N="FreeGB";E={[math]::Round($_.FreeSpace/1GB,2)}},
                      @{N="UsedGB";E={[math]::Round(($_.Size - $_.FreeSpace)/1GB,2)}},
                      @{N="FreePercent";E={[math]::Round(($_.FreeSpace/$_.Size)*100,1)}}

    $logicalDisks | Export-Csv "$OutputFolder\07a_Logical_Drives.csv" -NoTypeInformation

    # Physical disk SMART data
    $smartData = foreach ($disk in (Get-PhysicalDisk -ErrorAction SilentlyContinue)) {
        try {
            $rel = $disk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
            [PSCustomObject]@{
                Drive            = $disk.FriendlyName
                Model            = $disk.Model
                MediaType        = $disk.MediaType
                HealthStatus     = $disk.HealthStatus
                SizeGB           = [math]::Round($disk.Size/1GB,2)
                Temperature      = if ($rel.Temperature)    { "$($rel.Temperature) C" } else { "N/A" }
                ReadErrorsTotal  = if ($null -ne $rel.ReadErrorsTotal)  { $rel.ReadErrorsTotal }  else { "N/A" }
                WriteErrorsTotal = if ($null -ne $rel.WriteErrorsTotal) { $rel.WriteErrorsTotal } else { "N/A" }
                PowerOnHours     = if ($rel.PowerOnHours)   { $rel.PowerOnHours }   else { "N/A" }
                WearPercent      = if ($rel.Wear)            { "$($rel.Wear)%" }      else { "N/A" }
            }
        } catch {
            [PSCustomObject]@{
                Drive            = $disk.FriendlyName
                Model            = $disk.Model
                MediaType        = $disk.MediaType
                HealthStatus     = $disk.HealthStatus
                SizeGB           = [math]::Round($disk.Size/1GB,2)
                Temperature      = "Unavailable"
                ReadErrorsTotal  = "Unavailable"
                WriteErrorsTotal = "Unavailable"
                PowerOnHours     = "Unavailable"
                WearPercent      = "Unavailable"
            }
        }
    }

    $smartData | Export-Csv "$OutputFolder\07b_Disk_SMART.csv" -NoTypeInformation
    Write-Host "   Found $($logicalDisks.Count) logical drives and $($smartData.Count) physical disks." -ForegroundColor Green
} catch {
    Write-Host "   ERROR scanning disk info: $_" -ForegroundColor Red
}

# ============================================================
# 8. WINDOWS VERSION & BUILD
# ============================================================
Write-Host "[8/8] Collecting Windows version info..." -ForegroundColor Yellow

try {
    $os       = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $regBuild = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue

    [PSCustomObject]@{
        Caption          = $os.Caption
        Version          = $os.Version
        BuildNumber      = $os.BuildNumber
        DisplayVersion   = $regBuild.DisplayVersion
        ReleaseId        = $regBuild.ReleaseId
        UBR              = $regBuild.UBR
        Architecture     = $os.OSArchitecture
        InstallDate      = $os.InstallDate
        LastBootUpTime   = $os.LastBootUpTime
        RegisteredUser   = $os.RegisteredUser
        SerialNumber     = $os.SerialNumber
        SystemDrive      = $os.SystemDrive
        WindowsDirectory = $os.WindowsDirectory
    } | Export-Csv "$OutputFolder\08_Windows_Version.csv" -NoTypeInformation

    Write-Host "   $($os.Caption) — Build $($os.BuildNumber) ($($regBuild.DisplayVersion))" -ForegroundColor Green
} catch {
    Write-Host "   ERROR collecting Windows version: $_" -ForegroundColor Red
}

# ============================================================
# DONE
# ============================================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   Diagnostic scan complete!" -ForegroundColor Cyan
Write-Host "   All reports saved to:" -ForegroundColor Cyan
Write-Host "   $OutputFolder" -ForegroundColor White
Write-Host "============================================" -ForegroundColor Cyan
