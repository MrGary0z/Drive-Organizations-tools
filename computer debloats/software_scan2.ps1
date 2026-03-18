[CmdletBinding()]
param(
    [string]$OutputFolder,
    [switch]$SkipStoreApps,
    [switch]$SkipWinget
)

Set-StrictMode -Version Latest

$script:InventoryWarnings = [System.Collections.Generic.List[string]]::new()

function Add-InventoryWarning {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    $script:InventoryWarnings.Add($Message)
    Write-Warning $Message
}

function Get-DefaultOutputFolder {
    $desktopPath = [Environment]::GetFolderPath('Desktop')

    if ([string]::IsNullOrWhiteSpace($desktopPath)) {
        if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
            $desktopPath = Join-Path -Path $env:USERPROFILE -ChildPath 'Desktop'
        }
        else {
            $desktopPath = (Get-Location).Path
        }
    }

    return (Join-Path -Path $desktopPath -ChildPath 'Software_Scan')
}

function ConvertTo-InventoryDate {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return ''
    }

    $text = [string]$Value

    if ([string]::IsNullOrWhiteSpace($text)) {
        return ''
    }

    if ($text -match '^(\d{4})(\d{2})(\d{2})$') {
        return ('{0}-{1}-{2}' -f $matches[1], $matches[2], $matches[3])
    }

    $parsedDate = $null
    if ([DateTime]::TryParse($text, [ref]$parsedDate)) {
        return $parsedDate.ToString('yyyy-MM-dd')
    }

    return $text
}

function ConvertTo-InventoryText {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return ''
    }

    return ([string]$Value).Trim()
}

function Get-ObjectPropertyValue {
    param(
        [AllowNull()]
        [object]$InputObject,
        [Parameter(Mandatory)]
        [string]$PropertyName
    )

    if ($null -eq $InputObject) {
        return $null
    }

    $property = $InputObject.PSObject.Properties[$PropertyName]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function New-InventoryRecord {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [AllowNull()]
        [AllowEmptyString()]
        [object]$Version,
        [AllowNull()]
        [AllowEmptyString()]
        [object]$Publisher,
        [AllowNull()]
        [AllowEmptyString()]
        [object]$InstallDate,
        [AllowNull()]
        [AllowEmptyString()]
        [object]$InstallLocation,
        [AllowNull()]
        [AllowEmptyString()]
        [object]$UninstallCommand,
        [Parameter(Mandatory)]
        [string]$Source
    )

    [PSCustomObject]@{
        Name = (ConvertTo-InventoryText -Value $Name)
        Version = (ConvertTo-InventoryText -Value $Version)
        Publisher = (ConvertTo-InventoryText -Value $Publisher)
        InstallDate = (ConvertTo-InventoryDate -Value $InstallDate)
        InstallLocation = (ConvertTo-InventoryText -Value $InstallLocation)
        UninstallCommand = (ConvertTo-InventoryText -Value $UninstallCommand)
        Source = $Source
    }
}

function Get-SourcePriority {
    param(
        [Parameter(Mandatory)]
        [string]$Source
    )

    switch ($Source) {
        'Registry' { return 3 }
        'Microsoft Store' { return 2 }
        'Winget' { return 1 }
        default { return 0 }
    }
}

function Get-FieldValue {
    param(
        [Parameter(Mandatory)]
        [object]$Record,
        [Parameter(Mandatory)]
        [string]$PropertyName
    )

    return [string]$Record.$PropertyName
}

function Get-BestFieldValue {
    param(
        [Parameter(Mandatory)]
        [object[]]$Records,
        [Parameter(Mandatory)]
        [string]$PropertyName
    )

    foreach ($record in $Records) {
        $value = Get-FieldValue -Record $record -PropertyName $PropertyName
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
    }

    return ''
}

function Get-InventoryKey {
    param(
        [Parameter(Mandatory)]
        [object]$Record
    )

    $name = $Record.Name.ToLowerInvariant()
    $version = $Record.Version.ToLowerInvariant()
    $publisher = $Record.Publisher.ToLowerInvariant()

    return ('{0}|{1}|{2}' -f $name, $version, $publisher)
}

function Merge-InventoryRecords {
    param(
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[object]]$Records
    )

    $mergedRecords = [System.Collections.Generic.List[object]]::new()
    $groups = $Records | Group-Object -Property { Get-InventoryKey -Record $_ }

    foreach ($group in $groups) {
        $orderedRecords = $group.Group | Sort-Object -Property @(
            @{ Expression = { Get-SourcePriority -Source $_.Source }; Descending = $true },
            @{ Expression = { if ([string]::IsNullOrWhiteSpace($_.InstallLocation)) { 0 } else { 1 } }; Descending = $true },
            @{ Expression = { if ([string]::IsNullOrWhiteSpace($_.UninstallCommand)) { 0 } else { 1 } }; Descending = $true }
        )

        $primaryRecord = $orderedRecords[0]
        $sources = $orderedRecords.Source | Sort-Object -Unique

        $mergedRecords.Add([PSCustomObject]@{
            Name = $primaryRecord.Name
            Version = $primaryRecord.Version
            Publisher = (Get-BestFieldValue -Records $orderedRecords -PropertyName 'Publisher')
            InstallDate = (Get-BestFieldValue -Records $orderedRecords -PropertyName 'InstallDate')
            InstallLocation = (Get-BestFieldValue -Records $orderedRecords -PropertyName 'InstallLocation')
            UninstallCommand = (Get-BestFieldValue -Records $orderedRecords -PropertyName 'UninstallCommand')
            Source = ($sources -join '; ')
        })
    }

    return ($mergedRecords | Sort-Object -Property Name, Version, Publisher)
}

function Add-RegistryInventory {
    param(
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[object]]$Inventory
    )

    Write-Host 'Scanning registry uninstall entries...' -ForegroundColor Yellow

    $registryPaths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach ($path in $registryPaths) {
        try {
            $apps = Get-ItemProperty -Path $path -ErrorAction Stop

            foreach ($app in $apps) {
                $name = ConvertTo-InventoryText -Value (Get-ObjectPropertyValue -InputObject $app -PropertyName 'DisplayName')
                if ([string]::IsNullOrWhiteSpace($name)) {
                    continue
                }

                $Inventory.Add((New-InventoryRecord -Name $name -Version (Get-ObjectPropertyValue -InputObject $app -PropertyName 'DisplayVersion') -Publisher (Get-ObjectPropertyValue -InputObject $app -PropertyName 'Publisher') -InstallDate (Get-ObjectPropertyValue -InputObject $app -PropertyName 'InstallDate') -InstallLocation (Get-ObjectPropertyValue -InputObject $app -PropertyName 'InstallLocation') -UninstallCommand (Get-ObjectPropertyValue -InputObject $app -PropertyName 'UninstallString') -Source 'Registry'))
            }
        }
        catch {
            Add-InventoryWarning -Message ("Failed to read registry uninstall path '{0}': {1}" -f $path, $_.Exception.Message)
        }
    }
}

function Add-StoreInventory {
    param(
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[object]]$Inventory
    )

    Write-Host 'Scanning Microsoft Store apps...' -ForegroundColor Yellow

    try {
        $storeApps = Get-AppxPackage -ErrorAction Stop | Where-Object {
            $_.Name -and -not $_.IsFramework
        }

        foreach ($app in $storeApps) {
            $Inventory.Add((New-InventoryRecord -Name $app.Name -Version $app.Version -Publisher $app.Publisher -InstallDate $null -InstallLocation $app.InstallLocation -UninstallCommand $null -Source 'Microsoft Store'))
        }
    }
    catch {
        Add-InventoryWarning -Message ("Failed to enumerate Microsoft Store apps: {0}" -f $_.Exception.Message)
    }
}

function Get-WingetColumns {
    param(
        [Parameter(Mandatory)]
        [string]$HeaderLine
    )

    $matches = [regex]::Matches($HeaderLine, '\S(?:.*?\S)?(?=\s{2,}|\s*$)')
    $columns = [System.Collections.Generic.List[object]]::new()

    for ($index = 0; $index -lt $matches.Count; $index++) {
        $start = $matches[$index].Index
        $nextStart = if ($index -lt ($matches.Count - 1)) { $matches[$index + 1].Index } else { $HeaderLine.Length }

        $columns.Add([PSCustomObject]@{
            Name = $matches[$index].Value.Trim()
            Start = $start
            Length = ($nextStart - $start)
        })
    }

    return $columns
}

function ConvertFrom-WingetLine {
    param(
        [Parameter(Mandatory)]
        [string]$Line,
        [Parameter(Mandatory)]
        [object[]]$Columns
    )

    $result = [ordered]@{}

    for ($index = 0; $index -lt $Columns.Count; $index++) {
        $column = $Columns[$index]
        $start = [int]$column.Start

        if ($Line.Length -le $start) {
            $result[$column.Name] = ''
            continue
        }

        $maxLength = if ($index -lt ($Columns.Count - 1)) {
            [Math]::Min($Columns[$index + 1].Start, $Line.Length) - $start
        }
        else {
            $Line.Length - $start
        }

        $result[$column.Name] = $Line.Substring($start, $maxLength).Trim()
    }

    return [PSCustomObject]$result
}

function Add-WingetInventory {
    param(
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[object]]$Inventory
    )

    Write-Host 'Checking Winget packages...' -ForegroundColor Yellow

    $wingetCommand = Get-Command -Name winget -ErrorAction SilentlyContinue
    if (-not $wingetCommand) {
        Write-Host 'Winget not found. Skipping winget inventory.' -ForegroundColor DarkYellow
        return
    }

    try {
        $wingetOutput = & $wingetCommand.Source list --accept-source-agreements 2>$null
        $headerIndex = -1

        for ($index = 0; $index -lt $wingetOutput.Count; $index++) {
            if ($wingetOutput[$index] -match '^\s*Name\s{2,}') {
                $headerIndex = $index
                break
            }
        }

        if ($headerIndex -lt 0 -or ($headerIndex + 1) -ge $wingetOutput.Count) {
            throw 'Winget output did not contain a recognizable table header.'
        }

        $columns = Get-WingetColumns -HeaderLine $wingetOutput[$headerIndex]

        foreach ($line in ($wingetOutput | Select-Object -Skip ($headerIndex + 2))) {
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }

            if ($line -match '^-{3,}$') {
                continue
            }

            $package = ConvertFrom-WingetLine -Line $line -Columns $columns
            $name = ConvertTo-InventoryText -Value $package.Name

            if ([string]::IsNullOrWhiteSpace($name)) {
                continue
            }

            $packageId = ''
            if ($package.PSObject.Properties.Name -contains 'Id') {
                $packageId = ConvertTo-InventoryText -Value $package.Id
            }

            $uninstallTarget = if (-not [string]::IsNullOrWhiteSpace($packageId)) {
                "winget uninstall --id `"$packageId`""
            }
            else {
                "winget uninstall --name `"$name`""
            }

            $Inventory.Add((New-InventoryRecord -Name $name -Version $package.Version -Publisher $null -InstallDate $null -InstallLocation $null -UninstallCommand $uninstallTarget -Source 'Winget'))
        }
    }
    catch {
        Add-InventoryWarning -Message ("Failed to enumerate winget packages: {0}" -f $_.Exception.Message)
    }
}

Write-Host 'Scanning installed software...' -ForegroundColor Cyan

if ([string]::IsNullOrWhiteSpace($OutputFolder)) {
    $OutputFolder = Get-DefaultOutputFolder
}

try {
    New-Item -ItemType Directory -Path $OutputFolder -Force -ErrorAction Stop | Out-Null
}
catch {
    throw ("Unable to create output folder '{0}': {1}" -f $OutputFolder, $_.Exception.Message)
}

$inventory = [System.Collections.Generic.List[object]]::new()

Add-RegistryInventory -Inventory $inventory

if (-not $SkipStoreApps) {
    Add-StoreInventory -Inventory $inventory
}

if (-not $SkipWinget) {
    Add-WingetInventory -Inventory $inventory
}

Write-Host 'Consolidating inventory...' -ForegroundColor Yellow
$results = Merge-InventoryRecords -Records $inventory

$csvOutputFile = Join-Path -Path $OutputFolder -ChildPath 'installed_programs.csv'
$jsonOutputFile = Join-Path -Path $OutputFolder -ChildPath 'installed_programs.json'
$warningOutputFile = Join-Path -Path $OutputFolder -ChildPath 'inventory_warnings.log'

$results | Export-Csv -Path $csvOutputFile -NoTypeInformation -Encoding UTF8
$results | ConvertTo-Json -Depth 3 | Set-Content -Path $jsonOutputFile -Encoding UTF8

if ($script:InventoryWarnings.Count -gt 0) {
    $script:InventoryWarnings | Set-Content -Path $warningOutputFile -Encoding UTF8
}
elseif (Test-Path -Path $warningOutputFile) {
    Remove-Item -Path $warningOutputFile -Force
}

Write-Host ''
Write-Host 'Scan complete.' -ForegroundColor Green
Write-Host ("Total software records found: {0}" -f $results.Count)
Write-Host ("CSV results saved to: {0}" -f $csvOutputFile)
Write-Host ("JSON results saved to: {0}" -f $jsonOutputFile)

if ($script:InventoryWarnings.Count -gt 0) {
    Write-Host ("Warnings saved to: {0}" -f $warningOutputFile) -ForegroundColor DarkYellow
}