function Get-SMARTInfo {
    param(
        $CDIPath = "C:\temp\ninjarmm\crystaldiskinfo\"
    )
    
    $CDIExecutable = Join-Path -Path $CDIPath -ChildPath 'DiskInfo64.exe'
    Get-SMARTPreReq -crystalLocation $CDIExecutable

    try {
        Start-Process -FilePath $CDIExecutable -ArgumentList '/CopyExit' -Wait
    }
    catch {
        Write-Error "An error occurred: $_"
    }
    
    $warning = $false
    $DiskInfoRaw = Get-Content (Join-Path -Path $CDIPath -ChildPath 'DiskInfo.txt') -Raw
    # Line Exclusions to lower file size
    $excludePatterns = @(
        '^000:',
        '^(0x)?[0-9A-Fa-f]+:',
        '^-- IDENTIFY'
        '^-- SMART'
        '^-- SMART'
        '^\s{5}\+0'
        '^\s{8}0'
        '^\s*$' 
    )
    $filteredContent = $DiskInfoRaw -split "`n" | Where-Object { $line = $_; -not ($excludePatterns | Where-Object { $line -match $_ }) }
    $DiskInfo = $filteredContent -join "`n"
    $DriveInfoRegex = [regex] '(?m)(?<=\r?\n.+)(?:\r?\n^\s*(?<key>.+)\s:\s(?<value>.+))+(?=[\r\n\s]+-- S\.M\.A\.R\.T\.)'
    $smartalldrives = New-Object 'System.Collections.Generic.List[Object]'
    $i = 0
    
    foreach ($Drive in $DriveInfoRegex.Matches($DiskInfo)) {
        $DriveOutput = [ordered]@{}
        $Keys = $Drive.Groups['key'].Captures.Value
        $Values = $Drive.Groups['value'].Captures.Value
        for ($j = 0; $j -lt $Keys.Count; $j++) {
            $DriveOutput[$Keys[$j]] = $Values[$j]
        }
        $i++
        $smartalldrives.Add([PSCustomObject]$DriveOutput)
    }

    $smartFailedDrives = $smartAllDrives | Where-Object { $_."Health Status" -notlike "*Good*" }

    return $smartalldrives, $smartFailedDrives
}
