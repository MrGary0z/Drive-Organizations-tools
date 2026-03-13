[CmdletBinding()]
param (
    [int]$DaysOld = 365,
    [int]$LargeFileMB = 500
)

$ReportPath = "$PSScriptRoot/../reports/DDrive_COMPLETE_Audit.txt"
$CutoffDate = (Get-Date).AddDays(-$DaysOld)

# Ensure reports folder exists
$ReportDir = Split-Path $ReportPath
if (!(Test-Path $ReportDir)) {
    New-Item -ItemType Directory -Path $ReportDir | Out-Null
}

"==== COMPLETE D DRIVE AUDIT ====" | Out-File $ReportPath
"Generated: $(Get-Date)" | Out-File $ReportPath -Append
"" | Out-File $ReportPath -Append

# Disk Usage
$disk = Get-PSDrive D
"Disk Used: $([math]::Round(($disk.Used/1GB),2)) GB" | Out-File $ReportPath -Append
"Disk Free: $([math]::Round(($disk.Free/1GB),2)) GB" | Out-File $ReportPath -Append
"" | Out-File $ReportPath -Append

Write-Host "Scanning D:\ (this may take time)..."

# Single full scan
$AllFiles = Get-ChildItem D:\ -Recurse -File -ErrorAction SilentlyContinue

# Folder Size Breakdown (Top 20)
"--- Top 20 Largest Folders ---" | Out-File $ReportPath -Append
Get-ChildItem D:\ -Directory | ForEach-Object {
    $size = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue |
             Measure-Object -Property Length -Sum).Sum
    [PSCustomObject]@{
        Folder = $_.FullName
        SizeGB = [math]::Round($size / 1GB, 2)
    }
} | Sort-Object SizeGB -Descending |
Select-Object -First 20 |
Out-File $ReportPath -Append

"" | Out-File $ReportPath -Append

# Large Files
"--- Files Larger Than $LargeFileMB MB ---" | Out-File $ReportPath -Append
$AllFiles |
    Where-Object { $_.Length -gt ($LargeFileMB * 1MB) } |
    Select-Object FullName,
        @{Name="SizeMB";Expression={[math]::Round($_.Length/1MB,2)}} |
    Sort-Object SizeMB -Descending |
    Out-File $ReportPath -Append

"" | Out-File $ReportPath -Append

# Old Files
"--- Files Older Than $DaysOld Days ---" | Out-File $ReportPath -Append
$AllFiles |
    Where-Object { $_.LastWriteTime -lt $CutoffDate } |
    Select-Object FullName, LastWriteTime |
    Sort-Object LastWriteTime |
    Out-File $ReportPath -Append

"" | Out-File $ReportPath -Append

# ISO / Installer Files
"--- ISO / EXE / MSI Files ---" | Out-File $ReportPath -Append
$AllFiles |
    Where-Object { $_.Extension -match "\.iso|\.exe|\.msi" } |
    Select-Object FullName |
    Out-File $ReportPath -Append

"" | Out-File $ReportPath -Append

# Duplicate Detection (SHA256)
"--- Potential Duplicates (SHA256 Hash Match) ---" | Out-File $ReportPath -Append

$HashTable = @{}
foreach ($file in $AllFiles) {
    try {
        $hash = (Get-FileHash $file.FullName -Algorithm SHA256).Hash
        if ($HashTable.ContainsKey($hash)) {
            "Duplicate: $($file.FullName)" | Out-File $ReportPath -Append
        }
        else {
            $HashTable[$hash] = $file.FullName
        }
    } catch {}
}

"Audit Complete." | Out-File $ReportPath -Append
Write-Host "D Drive audit finished. Report saved to /reports folder."