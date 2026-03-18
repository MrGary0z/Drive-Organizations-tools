#Requires -RunAsAdministrator

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   System Diagnostic Tool v2.0" -ForegroundColor Cyan
Write-Host "   For Computer Repair Technicians" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Start timer and create output folder with timestamp so each scan is preserved
$ScanStartTime = Get-Date
$Timestamp    = $ScanStartTime.ToString("yyyy-MM-dd_HH-mm-ss")
$OutputFolder = "$env:USERPROFILE\Desktop\System_Scan\$Timestamp"
New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
Write-Host "Output folder: $OutputFolder" -ForegroundColor Green
Write-Host "Scan started at: $($ScanStartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Green
Write-Host ""

# Get currently logged-in user
$LoggedInUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
if ([string]::IsNullOrWhiteSpace($LoggedInUser)) {
    $LoggedInUser = $env:USERNAME
}

# Initialize summary tracking variables
$summaryData = @{
    ComputerName       = $env:COMPUTERNAME
    LoggedInUser       = $LoggedInUser
    ScanTimestamp      = $ScanStartTime.ToString('yyyy-MM-dd HH:mm:ss')
    RegistryAppsCount  = 0
    StoreAppsCount     = 0
    StartupCount       = 0
    ServicesCount      = 0
    TasksCount         = 0
    TotalRAMGB         = 0
    LogicalDrivesCount = 0
    WindowsVersion     = ""
    WindowsBuild       = ""
    DiskSpaceWarnings  = @()
}
Write-Host ""

# ============================================================
# 1. INSTALLED PROGRAMS (Registry)
# ============================================================
Write-Host "[1/13] Scanning installed programs..." -ForegroundColor Yellow

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

    $registryApps | Export-Csv "$OutputFolder\01_Installed_Programs.csv" -NoTypeInformation -Encoding UTF8
    $summaryData['RegistryAppsCount'] = $registryApps.Count
    Write-Host "   Found $($registryApps.Count) registry programs." -ForegroundColor Green
} catch {
    Write-Host "   ERROR scanning registry programs: $_" -ForegroundColor Red
}

# ============================================================
# 2. MICROSOFT STORE APPS
# ============================================================
Write-Host "[2/13] Scanning Microsoft Store apps..." -ForegroundColor Yellow

try {
    $storeApps = Get-AppxPackage -AllUsers -ErrorAction Stop |
        Select-Object @{N="Name";E={$_.Name}},
                      @{N="Version";E={$_.Version}},
                      @{N="Publisher";E={$_.Publisher}},
                      @{N="PackageFullName";E={$_.PackageFullName}},
                      @{N="InstallLocation";E={$_.InstallLocation}} |
        Sort-Object Name -Unique

    $storeApps | Export-Csv "$OutputFolder\02_Store_Apps.csv" -NoTypeInformation -Encoding UTF8
    $summaryData['StoreAppsCount'] = $storeApps.Count
    Write-Host "   Found $($storeApps.Count) Store apps." -ForegroundColor Green
} catch {
    Write-Host "   ERROR scanning Store apps: $_" -ForegroundColor Red
}

# ============================================================
# 3. STARTUP PROGRAMS
# ============================================================
Write-Host "[3/13] Scanning startup programs..." -ForegroundColor Yellow

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
    $allStartup | Export-Csv "$OutputFolder\03_Startup_Programs.csv" -NoTypeInformation -Encoding UTF8
    $summaryData['StartupCount'] = $allStartup.Count
    Write-Host "   Found $($allStartup.Count) startup entries." -ForegroundColor Green
} catch {
    Write-Host "   ERROR scanning startup programs: $_" -ForegroundColor Red
}

# ============================================================
# 4. SERVICES
# ============================================================
Write-Host "[4/13] Scanning services..." -ForegroundColor Yellow

try {
    $services = Get-Service -ErrorAction Stop |
        Select-Object Name, DisplayName, Status, StartType |
        Sort-Object Status, DisplayName

    $services | Export-Csv "$OutputFolder\04_Services.csv" -NoTypeInformation -Encoding UTF8
    $summaryData['ServicesCount'] = $services.Count
    $runningCount = ($services | Where-Object { $_.Status -eq "Running" }).Count
    Write-Host "   Found $($services.Count) services ($runningCount running)." -ForegroundColor Green
} catch {
    Write-Host "   ERROR scanning services: $_" -ForegroundColor Red
}

# ============================================================
# 5. SCHEDULED TASKS
# ============================================================
Write-Host "[5/13] Scanning scheduled tasks..." -ForegroundColor Yellow

try {
    $tasks = Get-ScheduledTask -ErrorAction Stop |
        Select-Object TaskName,
                      TaskPath,
                      State,
                      @{N="RunAsUser";E={$_.Principal.UserId}},
                      @{N="Description";E={$_.Description}} |
        Sort-Object TaskPath, TaskName

    $tasks | Export-Csv "$OutputFolder\05_Scheduled_Tasks.csv" -NoTypeInformation -Encoding UTF8
    $summaryData['TasksCount'] = $tasks.Count
    Write-Host "   Found $($tasks.Count) scheduled tasks." -ForegroundColor Green
} catch {
    Write-Host "   ERROR scanning scheduled tasks: $_" -ForegroundColor Red
}

# ============================================================
# 6. HARDWARE INFORMATION
# ============================================================
Write-Host "[6/13] Scanning hardware..." -ForegroundColor Yellow

try {
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue |
        Select-Object @{N="Component";E={"CPU"}},
                      @{N="Name";E={$_.Name}},
                      @{N="Detail";E={"Cores: $($_.NumberOfCores) | Logical: $($_.NumberOfLogicalProcessors) | Max Speed: $($_.MaxClockSpeed) MHz"}}

    $ramModules = Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue
    $totalRAM   = [math]::Round(($ramModules | Measure-Object Capacity -Sum).Sum / 1GB, 2)
    $summaryData['TotalRAMGB'] = $totalRAM
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
    $hardware | Export-Csv "$OutputFolder\06_Hardware_Info.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "   Hardware collected. Total RAM: $totalRAM GB." -ForegroundColor Green
} catch {
    Write-Host "   ERROR scanning hardware: $_" -ForegroundColor Red
}

# ============================================================
# 7. DISK HEALTH
# ============================================================
Write-Host "[7/13] Scanning disk health..." -ForegroundColor Yellow

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

    $logicalDisks | Export-Csv "$OutputFolder\07a_Logical_Drives.csv" -NoTypeInformation -Encoding UTF8
    $summaryData['LogicalDrivesCount'] = $logicalDisks.Count

    # Check for low disk space warning (less than 10% free)
    foreach ($disk in $logicalDisks) {
        if ($disk.FreePercent -lt 10) {
            $warning = "Drive $($disk.DeviceID) has only $($disk.FreePercent)% free space ($($disk.FreeGB) GB free)"
            $summaryData['DiskSpaceWarnings'] += $warning
            Write-Host "   WARNING: $warning" -ForegroundColor Yellow
        }
    }

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

    $smartData | Export-Csv "$OutputFolder\07b_Disk_SMART.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "   Found $($logicalDisks.Count) logical drives and $($smartData.Count) physical disks." -ForegroundColor Green
} catch {
    Write-Host "   ERROR scanning disk info: $_" -ForegroundColor Red
}

# ============================================================
# 8. WINDOWS VERSION & BUILD
# ============================================================
Write-Host "[8/13] Collecting Windows version info..." -ForegroundColor Yellow

try {
    $os       = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $regBuild = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue

    $osInfo = [PSCustomObject]@{
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
    }
    $osInfo | Export-Csv "$OutputFolder\08_Windows_Version.csv" -NoTypeInformation -Encoding UTF8

    # Capture for summary
    $summaryData['WindowsVersion'] = $os.Caption
    $summaryData['WindowsBuild'] = "$($os.BuildNumber) ($($regBuild.DisplayVersion))"

    Write-Host "   $($os.Caption) — Build $($os.BuildNumber) ($($regBuild.DisplayVersion))" -ForegroundColor Green
} catch {
    Write-Host "   ERROR collecting Windows version: $_" -ForegroundColor Red
}

# ============================================================
# 9. RUNNING PROCESSES
# ============================================================
Write-Host "[9/13] Scanning running processes..." -ForegroundColor Yellow

try {
    $processes = @()
    foreach ($proc in (Get-Process -ErrorAction SilentlyContinue)) {
        $cpuPercent = 0
        $startTime = $null
        
        # Safely calculate CPU percentage, handling processes with no StartTime
        if ($null -ne $proc.StartTime) {
            $processRuntime = (Get-Date) - $proc.StartTime
            if ($processRuntime.TotalSeconds -gt 0) {
                $cpuPercent = [math]::Round(($proc.CPU / $processRuntime.TotalSeconds) * 100, 2)
            }
            $startTime = $proc.StartTime
        } else {
            $cpuPercent = 0
            $startTime = $null
        }
        
        $processes += [PSCustomObject]@{
            ProcessName = $proc.Name
            PID         = $proc.Id
            CPUPercent  = $cpuPercent
            MemoryMB    = [math]::Round($proc.WorkingSet / 1MB, 2)
            Path        = if ($proc.Path) { $proc.Path } else { "N/A" }
            StartTime   = if ($startTime) { $startTime } else { "N/A" }
        }
    }
    
    $processes = $processes | Sort-Object MemoryMB -Descending
    $processes | Export-Csv "$OutputFolder\09_Running_Processes.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "   Found $($processes.Count) running processes." -ForegroundColor Green
} catch {
    Write-Host "   ERROR scanning running processes: $_" -ForegroundColor Red
}

# ============================================================
# 10. NETWORK DIAGNOSTICS
# ============================================================
Write-Host "[10/13] Scanning network adapters and connections..." -ForegroundColor Yellow

try {
    # 10a. Network Adapters
    $adapters = Get-NetAdapter -ErrorAction SilentlyContinue |
        Select-Object @{N="Name";E={$_.Name}},
                      @{N="Status";E={$_.Status}},
                      @{N="LinkSpeed";E={$_.LinkSpeed}},
                      @{N="MediaType";E={$_.MediaType}},
                      @{N="MacAddress";E={$_.MacAddress}},
                      @{N="DriverDescription";E={$_.DriverDescription}} |
        Sort-Object Name

    $adapters | Export-Csv "$OutputFolder\10a_Network_Adapters.csv" -NoTypeInformation -Encoding UTF8

    # 10b. IP Addresses
    $ipAddresses = Get-NetIPAddress -ErrorAction SilentlyContinue |
        Select-Object @{N="InterfaceAlias";E={$_.InterfaceAlias}},
                      @{N="AddressFamily";E={$_.AddressFamily}},
                      @{N="IPAddress";E={$_.IPAddress}},
                      @{N="PrefixLength";E={$_.PrefixLength}},
                      @{N="Type";E={$_.Type}} |
        Sort-Object InterfaceAlias, AddressFamily

    $ipAddresses | Export-Csv "$OutputFolder\10b_IP_Addresses.csv" -NoTypeInformation -Encoding UTF8

    # 10c. TCP Connections
    $tcpConnections = Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
        Select-Object @{N="LocalAddress";E={$_.LocalAddress}},
                      @{N="LocalPort";E={$_.LocalPort}},
                      @{N="RemoteAddress";E={$_.RemoteAddress}},
                      @{N="RemotePort";E={$_.RemotePort}},
                      @{N="State";E={$_.State}},
                      @{N="OwningProcess";E={$_.OwningProcess}} |
        Sort-Object LocalAddress, LocalPort

    $tcpConnections | Export-Csv "$OutputFolder\10c_TCP_Connections.csv" -NoTypeInformation -Encoding UTF8

    Write-Host "   Found $($adapters.Count) network adapters." -ForegroundColor Green
    Write-Host "   Found $($ipAddresses.Count) IP addresses." -ForegroundColor Green
    Write-Host "   Found $($tcpConnections.Count) established TCP connections." -ForegroundColor Green
} catch {
    Write-Host "   ERROR scanning network info: $_" -ForegroundColor Red
}

# ============================================================
# 11. INSTALLED DRIVERS
# ============================================================
Write-Host "[11/13] Scanning installed drivers..." -ForegroundColor Yellow

try {
    $drivers = Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop |
        Select-Object @{N="DeviceName";E={$_.DeviceName}},
                      @{N="DriverVersion";E={$_.DriverVersion}},
                      @{N="Manufacturer";E={$_.Manufacturer}},
                      @{N="DriverDate";E={$_.DriverDate}},
                      @{N="Signer";E={$_.Signer}} |
        Sort-Object DeviceName

    $drivers | Export-Csv "$OutputFolder\11_Drivers.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "   Found $($drivers.Count) signed device drivers." -ForegroundColor Green
} catch {
    Write-Host "   ERROR scanning drivers: $_" -ForegroundColor Red
}

# ============================================================
# 12. SYSTEM EVENT LOG (Last 100 Errors)
# ============================================================
Write-Host "[12/13] Scanning system event log..." -ForegroundColor Yellow

try {
    # Use FilterHashtable for efficient query of Critical and Error events only
    $filterHashtable = @{
        LogName   = 'System'
        Level     = @(1, 2)  # 1=Critical, 2=Error
    }
    
    try {
        $eventLog = Get-WinEvent -FilterHashtable $filterHashtable -MaxEvents 100 -ErrorAction Stop |
            Select-Object @{N="TimeCreated";E={$_.TimeCreated}},
                          @{N="EventID";E={$_.Id}},
                          @{N="Level";E={$_.LevelDisplayName}},
                          @{N="ProviderName";E={$_.ProviderName}},
                          @{N="Message";E={$_.Message}} |
            Sort-Object TimeCreated -Descending
    } catch {
        # Fallback if FilterHashtable doesn't work (older systems)
        $eventLog = Get-WinEvent -LogName System -MaxEvents 100 -ErrorAction SilentlyContinue |
            Where-Object { $_.LevelDisplayName -eq "Error" -or $_.LevelDisplayName -eq "Critical" } |
            Select-Object @{N="TimeCreated";E={$_.TimeCreated}},
                          @{N="EventID";E={$_.Id}},
                          @{N="Level";E={$_.LevelDisplayName}},
                          @{N="ProviderName";E={$_.ProviderName}},
                          @{N="Message";E={$_.Message}} |
            Sort-Object TimeCreated -Descending
    }

    $eventLog | Export-Csv "$OutputFolder\12_System_Events.csv" -NoTypeInformation -Encoding UTF8
    $errorCount = ($eventLog | Where-Object { $_.Level -eq "Error" -or $_.Level -eq "Critical" }).Count
    Write-Host "   Found $($eventLog.Count) critical/error event log entries." -ForegroundColor Green
} catch {
    Write-Host "   ERROR scanning event log: $_" -ForegroundColor Red
}

# ============================================================
# 13. WINDOWS DEFENDER STATUS
# ============================================================
Write-Host "[13/13] Checking Windows Defender status..." -ForegroundColor Yellow

try {
    # Call Get-MpComputerStatus once and reuse for all properties
    $mpPref = Get-MpPreference -ErrorAction Stop
    $mpStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue
    
    $defenderStatus = [PSCustomObject]@{
        RealTimeProtectionEnabled  = if ($null -ne $mpPref.DisableRealtimeMonitoring) { -not $mpPref.DisableRealtimeMonitoring } else { $false }
        AntivirusEnabled           = if ($null -ne $mpStatus) { $mpStatus.AntivirusEnabled } else { $false }
        AntiSpywareEnabled         = if ($null -ne $mpStatus) { $mpStatus.AntispywareEnabled } else { $false }
        OnAccessProtectionEnabled  = if ($null -ne $mpPref.DisableOnAccessProtection) { -not $mpPref.DisableOnAccessProtection } else { $false }
        SignatureLastUpdated       = if ($null -ne $mpStatus) { $mpStatus.AntivirusSignatureLastUpdated } else { "N/A" }
        FullScanLastRun            = if ($null -ne $mpStatus) { $mpStatus.FullScanStartTime } else { "N/A" }
    }

    $defenderStatus | Export-Csv "$OutputFolder\13_Defender_Status.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "   Real-time protection: $($defenderStatus.RealTimeProtectionEnabled)" -ForegroundColor Green
    Write-Host "   Antivirus enabled: $($defenderStatus.AntivirusEnabled)" -ForegroundColor Green
    Write-Host "   Antispyware enabled: $($defenderStatus.AntiSpywareEnabled)" -ForegroundColor Green
} catch {
    Write-Host "   ERROR checking Defender status: $_" -ForegroundColor Red
}

# ============================================================
# DONE - Export Summary and Compress Report
# ============================================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   Finalizing diagnostic report..." -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Export summary report as the first file
try {
    # Convert disk warnings array to string if present
    $summaryForExport = $summaryData.Clone()
    if ($summaryForExport.DiskSpaceWarnings -is [object[]]) {
        $summaryForExport.DiskSpaceWarnings = $summaryForExport.DiskSpaceWarnings -join "; "
    }
    
    [PSCustomObject]$summaryForExport | Export-Csv "$OutputFolder\00_System_Summary.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "✓ System Summary report generated." -ForegroundColor Green
} catch {
    Write-Host "   ERROR generating summary report: $_" -ForegroundColor Red
}

# Calculate scan duration
$ScanEndTime = Get-Date
$ScanDuration = $ScanEndTime - $ScanStartTime
$durationString = "{0}h {1}m {2}s" -f $ScanDuration.Hours, $ScanDuration.Minutes, $ScanDuration.Seconds

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   Diagnostic scan complete!" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Summary:" -ForegroundColor Yellow
Write-Host "   Computer: $($summaryData.ComputerName)" -ForegroundColor White
Write-Host "   Logged In User: $($summaryData.LoggedInUser)" -ForegroundColor White
Write-Host "   Windows: $($summaryData.WindowsVersion)" -ForegroundColor White
Write-Host "   Build: $($summaryData.WindowsBuild)" -ForegroundColor White
Write-Host "   Total RAM: $($summaryData.TotalRAMGB) GB" -ForegroundColor White
Write-Host "   Installed programs: $($summaryData.RegistryAppsCount)" -ForegroundColor White
Write-Host "   Scan duration: $durationString" -ForegroundColor Cyan
if ($summaryData.DiskSpaceWarnings.Count -gt 0) {
    Write-Host "" 
    Write-Host "   ⚠ DISK SPACE WARNINGS:" -ForegroundColor Yellow
    foreach ($warning in $summaryData.DiskSpaceWarnings) {
        Write-Host "      - $warning" -ForegroundColor Yellow
    }
}
Write-Host ""
Write-Host "Reports saved to:" -ForegroundColor Cyan
Write-Host "   $OutputFolder" -ForegroundColor White
Write-Host ""

# Compress the report folder into a ZIP file
try {
    $ZipPath = "$env:USERPROFILE\Desktop\System_Scan\Diagnostic_Report_$($Timestamp).zip"
    Write-Host "Compressing report folder..." -ForegroundColor Yellow
    
    if (Get-Command Compress-Archive -ErrorAction SilentlyContinue) {
        Compress-Archive -Path "$OutputFolder\*" -DestinationPath $ZipPath -Force
        Write-Host "✓ Report compressed to: $ZipPath" -ForegroundColor Green
    } else {
        Write-Host "   INFO: Compress-Archive not available; skipping ZIP creation." -ForegroundColor Yellow
    }
} catch {
    Write-Host "   Warning: Could not compress report folder: $_" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   Reports ready for technician review!" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
