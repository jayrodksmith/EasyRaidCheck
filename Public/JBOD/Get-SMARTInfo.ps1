function Get-SMARTInfo {
    param(
        $CDIPath = "C:\ProgramData\EasyRaidCheck\CrystalDiskInfo\DiskInfo64.exe"
    )
    
    $CDIExecutable = $CDIPath
    Get-SMARTPreReq -crystalLocation $CDIExecutable

    try {
        Start-Process -FilePath $CDIExecutable -ArgumentList '/CopyExit' -Wait
    }
    catch {
        Write-Error "An error occurred: $_"
    }
    
    $smartalldrives = @()

    $drive = $null

    Get-Content -Path "C:\ProgramData\EasyRaidCheck\Crystaldiskinfo\DiskInfo.txt" | ForEach-Object {
        if ($_ -match 'Model : (.*)') {
            if ($drive) {
                $smartalldrives += $drive
            }
            $drive = New-Object PSObject -Property @{
                Model = $matches[1]
            }
        }
        elseif ($_ -match 'Firmware : (.*)') {
            $drive | Add-Member -MemberType NoteProperty -Name "Firmware" -Value $matches[1]
        }
        elseif ($_ -match 'Serial Number : (.*)') {
            $drive | Add-Member -MemberType NoteProperty -Name "Serial Number" -Value $matches[1]
        }
        elseif ($_ -match 'Disk Size : (.*)') {
            $sizevalue = $matches[1] -replace '\s*\(.*\)', ''
            $drive | Add-Member -MemberType NoteProperty -Name "Disk Size" -Value $sizevalue
        }
        elseif ($_ -match 'Interface : (.*)') {
            $interfacevalue = $matches[1] -replace '\s*\(.*\)', ''
            $drive | Add-Member -MemberType NoteProperty -Name "Interface" -Value $interfacevalue
        }
        elseif ($_ -match 'Health Status : (.*)') {
            $drive | Add-Member -MemberType NoteProperty -Name "Health Status" -Value $matches[1]
            if ($drive.'Health Status' -notmatch '\bGood\b' -and $null -ne $drive.'Health Status' -and $drive.'Health Status' -notmatch '\bUnknown\b') {
                $drive | Add-Member -MemberType NoteProperty -Name "RowColour" -Value 'danger'
            } else {
                $drive | Add-Member -MemberType NoteProperty -Name "RowColour" -Value 'success'
            }
        }
        elseif ($_ -match 'Power On Hours : (.*)') {
            $drive | Add-Member -MemberType NoteProperty -Name "Power On Hours" -Value $matches[1]
        }
        elseif ($_ -match 'Temperature : (.*)') {
            $temperaturevalue = $matches[1] -replace '\s*\(.*\)', ''
            $drive | Add-Member -MemberType NoteProperty -Name "Temperature" -Value $temperaturevalue
        }
        elseif ($_ -match 'Drive Letter : (.*)') {
            $drive | Add-Member -MemberType NoteProperty -Name "Drive Letter" -Value $matches[1]
            $smartalldrives += $drive
            $drive = $null
        }
    }

    if ($drive) {
        $smartalldrives += $drive
    }

    $smartFailedDrives = $smartalldrives | Where-Object { $_."Health Status" -notlike "*Good*" }
    return $smartalldrives, $smartFailedDrives
}