[CmdletBinding()]
param (
    [int]$DaysOld = 365,
    [int]$LargeFileMB = 500,

    # organization options
    [string]$ArchiveRoot = "$PSScriptRoot/../archive",
    [switch]$MoveLarge,
    [switch]$MoveOld,
    [switch]$MoveInstallers,
    [switch]$DeleteDuplicates,
    [switch]$DryRun
)

$ReportPath = "$PSScriptRoot/../reports/CDrive_COMPLETE_Audit.txt"
$CutoffDate = (Get-Date).AddDays(-$DaysOld)

# Ensure reports folder exists
$ReportDir = Split-Path $ReportPath
if (!(Test-Path $ReportDir)) {
    New-Item -ItemType Directory -Path $ReportDir | Out-Null
}

# prepare archive directories if any action is requested
if ($MoveLarge -or $MoveOld -or $MoveInstallers -or $DeleteDuplicates) {
    if (!(Test-Path $ArchiveRoot)) {
        New-Item -ItemType Directory -Path $ArchiveRoot | Out-Null
    }
}

"==== COMPLETE C DRIVE AUDIT ====" | Out-File $ReportPath
"Generated: $(Get-Date)" | Out-File $ReportPath -Append
"" | Out-File $ReportPath -Append

# Disk Usage
$disk = Get-PSDrive C
"Disk Used: $([math]::Round(($disk.Used/1GB),2)) GB" | Out-File $ReportPath -Append
"Disk Free: $([math]::Round(($disk.Free/1GB),2)) GB" | Out-File $ReportPath -Append
"" | Out-File $ReportPath -Append

Write-Host "Scanning C:\ (this may take time)..."

# Single full scan
$AllFiles = Get-ChildItem C:\ -Recurse -File -ErrorAction SilentlyContinue

# classify categories once
$LargeFiles = $AllFiles | Where-Object { $_.Length -gt ($LargeFileMB * 1MB) }
$OldFiles = $AllFiles | Where-Object { $_.LastWriteTime -lt $CutoffDate }
$InstallerFiles = $AllFiles | Where-Object { $_.Extension -match "\.iso|\.exe|\.msi" }

# Large Files
"--- Files Larger Than $LargeFileMB MB ---" | Out-File $ReportPath -Append
$LargeFiles |
    Select-Object FullName,
        @{Name="SizeMB";Expression={[math]::Round($_.Length/1MB,2)}} |
    Sort-Object SizeMB -Descending |
    Out-File $ReportPath -Append

# optionally move
if ($MoveLarge -and $LargeFiles) {
    $dest = Join-Path $ArchiveRoot 'Large'
    if (!(Test-Path $dest)) { New-Item -ItemType Directory -Path $dest | Out-Null }
    foreach ($f in $LargeFiles) {
        "Moving $($f.FullName) -> $dest" | Out-File $ReportPath -Append
        if (-not $DryRun) { Move-Item -Path $f.FullName -Destination $dest -Force }
    }
}

"" | Out-File $ReportPath -Append

# Old Files
"--- Files Older Than $DaysOld Days ---" | Out-File $ReportPath -Append
$OldFiles |
    Select-Object FullName, LastWriteTime |
    Sort-Object LastWriteTime |
    Out-File $ReportPath -Append

if ($MoveOld -and $OldFiles) {
    $dest = Join-Path $ArchiveRoot 'Old'
    if (!(Test-Path $dest)) { New-Item -ItemType Directory -Path $dest | Out-Null }
    foreach ($f in $OldFiles) {
        "Moving $($f.FullName) -> $dest" | Out-File $ReportPath -Append
        if (-not $DryRun) { Move-Item -Path $f.FullName -Destination $dest -Force }
    }
}

"" | Out-File $ReportPath -Append

# ISO / Installer Files
"--- ISO / EXE / MSI Files ---" | Out-File $ReportPath -Append
$InstallerFiles |
    Select-Object FullName |
    Out-File $ReportPath -Append

if ($MoveInstallers -and $InstallerFiles) {
    $dest = Join-Path $ArchiveRoot 'Installers'
    if (!(Test-Path $dest)) { New-Item -ItemType Directory -Path $dest | Out-Null }
    foreach ($f in $InstallerFiles) {
        "Moving $($f.FullName) -> $dest" | Out-File $ReportPath -Append
        if (-not $DryRun) { Move-Item -Path $f.FullName -Destination $dest -Force }
    }
}

"" | Out-File $ReportPath -Append

# Duplicate Detection (SHA256)
"--- Potential Duplicates (SHA256 Hash Match) ---" | Out-File $ReportPath -Append

$HashTable = @{}
$DuplicateFiles = @()
foreach ($file in $AllFiles) {
    try {
        $hash = (Get-FileHash $file.FullName -Algorithm SHA256).Hash
        if ($HashTable.ContainsKey($hash)) {
            "Duplicate: $($file.FullName)" | Out-File $ReportPath -Append
            $DuplicateFiles += $file
        }
        else {
            $HashTable[$hash] = $file.FullName
        }
    } catch {}
}

if ($DeleteDuplicates -and $DuplicateFiles) {
    $dest = Join-Path $ArchiveRoot 'Duplicates'
    if (!(Test-Path $dest)) { New-Item -ItemType Directory -Path $dest | Out-Null }
    foreach ($f in $DuplicateFiles) {
        "Removing duplicate $($f.FullName)" | Out-File $ReportPath -Append
        if (-not $DryRun) {
            if ($MoveLarge -or $MoveOld -or $MoveInstallers) {
                Move-Item -Path $f.FullName -Destination $dest -Force
            } else {
                Remove-Item -Path $f.FullName -Force
            }
        }
    }
}

"Audit Complete." | Out-File $ReportPath -Append
Write-Host "Audit finished. Report saved to /reports folder."