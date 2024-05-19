function Get-RaidControllerPERC {
    [CmdletBinding()]
    param (
        [string]$percCLILocation = 'C:\ProgramData\EasyRaidCheck\Dell\perccli64.exe'
    )

    Get-RaidControllerPERCPreReq -PERCCLILocation $percCLILocation

    $alldrives              = New-Object System.Collections.Generic.List[Object]
    $missingdrives          = New-Object System.Collections.Generic.List[Object]
    $failedvirtualdrives    = New-Object System.Collections.Generic.List[Object]
    $raidarraydetails       = New-Object System.Collections.Generic.List[Object]
    $virtualdrivesgroup     = New-Object System.Collections.Generic.List[Object]
    $virtualdrives          = New-Object System.Collections.Generic.List[Object]

    try {
        $ExecutepercCLICommandbasicinfo     = & $percCLILocation "show all"
        $controllerCountMatch               = $ExecutepercCLICommandbasicinfo | Select-String -Pattern "Number of Controllers\s*=\s*(\d+)"
        $controllerCountString              = $controllerCountMatch.Matches.Groups[1].Value.Trim()

        # Debug output to verify the controller count
        Write-Verbose "Controller Count String: $controllerCountString"

        if ($controllerCountString -match '^\d+$') {
            $controllerCount = [int]$controllerCountString.Trim()
            Write-Verbose "Controller Count (Parsed as Int): $controllerCount"
        } else {
            throw "Failed to parse the number of controllers"
        }

        for ($i = 0; $i -lt $controllerCount; $i++) {
            $controller = "/c$i"
            $controllertrimmed = $controller -replace "/c", ""

            Write-Verbose "Processing Controller: $controller"
            
            $percCLICommandvirtualdrive             = "$controller /vall show j"
            $percCLICommandvirtualdrivegroup        = "$controller /dall show j"
            $percCLICommandphysical                 = "$controller /eall /sall show j"
            $percCLICommandphysicalall              = "$controller /eall /sall show all"
            $percCLICommandbasicinfo2               = "$controller show"
            $percCLICommandrebuildprogress          = "$controller /eall /sall show rebuild"

            $ExecutepercCLIvirtualdrive             = & $percCLILocation $percCLICommandvirtualdrive | out-string
            $ArraypercCLIvirtualdrive               = ConvertFrom-Json $ExecutepercCLIvirtualdrive
            $ExecutepercCLIvirtualdrivegroup        = & $percCLILocation $percCLICommandvirtualdrivegroup | out-string
            $ArraypercCLIvirtualdrivegroup          = ConvertFrom-Json $ExecutepercCLIvirtualdrivegroup
            $ExecutepercCLICommandbasicinfo2        = & $percCLILocation $percCLICommandbasicinfo2
            $ExecutepercCLICommandrebuildprogress   = & $percCLILocation $percCLICommandrebuildprogress

            $PERCcontrollermodel                     = $ExecutepercCLICommandbasicinfo2 | Select-String -Pattern "Product Name\s*=\s*(.*)" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() }
            $PERCcontrollerserial                    = $ExecutepercCLICommandbasicinfo2 | Select-String -Pattern "Serial Number\s*=\s*(.*)" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() }
            $PERCcontrollerfirmware                  = $ExecutepercCLICommandbasicinfo2 | Select-String -Pattern "FW Version\s*=\s*(.*)" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() }
            $PERCcontrollerdriver                    = $ExecutepercCLICommandbasicinfo2 | Select-String -Pattern "Driver Version\s*=\s*(.*)" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() }

            # Get Virtual Drive Status + Physical
            foreach ($VirtualDrivegroup in $ArraypercCLIvirtualdrivegroup.Controllers.'response data'.'response data'.'TOPOLOGY') {
                $RowColour = switch ($($VirtualDrivegroup.State)) {
                    { $_ -eq 'Onln' } { "success"; break }
                    { $_ -eq 'Optl' } { "success"; break }
                    default { "danger" }
                }
                $virtualdrivesgroup.Add([PSCustomObject]@{
                    DriveGroup      = $($VirtualDrivegroup.'DG')
                    Array           = $($VirtualDrivegroup.'Arr')
                    Row             = $($VirtualDrivegroup.'Row')
                    'EID:Slot'      = $($VirtualDrivegroup.'EID:Slot')
                    DID             = $($VirtualDrivegroup.'DID')
                    Type            = $($VirtualDrivegroup.'Type')
                    Status          = $($VirtualDrivegroup.'State')
                    Size            = $($VirtualDrivegroup.'Size')
                    RowColour       = $RowColour
                })
            }

            # Get Virtual Drive Status
            foreach ($VirtualDrive in $ArraypercCLIvirtualdrive.Controllers.'response data'.'Virtual Drives') {
                $RowColour = switch ($($VirtualDrive.State)) {
                    { $_ -eq 'Optl' } { "success"; break }
                    default { "danger" }
                }
                if ($($VirtualDrive.'Cache') -eq 'RWBD') {
                    $ReadAhead = $true
                    $WriteBack = $true
                }
                if ($($VirtualDrive.'Cache') -eq 'RAWBD') {
                    $ReadAhead = $true
                    $WriteBack = $true
                }
                if ($($VirtualDrive.'Cache') -eq 'NRWTD') {
                    $ReadAhead = $false
                    $WriteBack = $false
                }
                if ($($VirtualDrive.'Cache') -eq 'RWTD') {
                    $ReadAhead = $true
                    $WriteBack = $true
                }
                if ($($VirtualDrive.'Cache') -eq 'NRWBD') {
                    $ReadAhead = $false
                    $WriteBack = $true
                }
                if ($($VirtualDrive.'Cache') -eq 'NRAWBD') {
                    $ReadAhead = $false
                    $WriteBack = $true
                }
                $virtualdrives.Add([PSCustomObject]@{
                    Controller      = $controllertrimmed
                    Array           = $($VirtualDrive.'DG/VD')
                    Type            = $($VirtualDrive.'TYPE')
                    Status          = $($VirtualDrive.'State')
                    Access          = $($VirtualDrive.'Access')
                    Cache           = $($VirtualDrive.'Cache')
                    ReadAhead       = $ReadAhead
                    WriteBack       = $WriteBack
                    Size            = $($VirtualDrive.'Size')
                    Name            = $($VirtualDrive.'Name')
                    RowColour       = $RowColour
                })
            }

            $ExecutepercCLIphysical     = & $percCLILocation $percCLICommandphysical | out-string
            $ArraypercCLIphysical       = ConvertFrom-Json $ExecutepercCLIphysical
            $ExecutepercCLIphysicalall  = & $percCLILocation $percCLICommandphysicalall | out-string
            $driveEntries               = $ExecutepercCLIphysicalall -split [System.Environment]::NewLine
            $driveObjects = @()

            foreach ($line in $driveEntries) {
                if ($line -match "^Drive /c$i/e(\d+)/s(\d+)") {
                    $driveIdentifier = "$($Matches[1]):$($Matches[2])"
                }
                elseif ($line -match "^SN =") {
                    $serialNumber = $line -replace "SN = ", ""
                    $serialNumber = $serialNumber -replace "\s", ""

                    $driveObject = [PSCustomObject]@{
                        DriveIdentifier = $driveIdentifier
                        SerialNumber = $serialNumber
                    }
                    $driveObjects += $driveObject
                }
            }

            foreach ($physicaldrive in $ArraypercCLIphysical.Controllers.'Response data'.'Drive Information') {
                $RowColour = switch ($($physicaldrive.State)) {
                    { $_ -eq 'Onln' } { "success"; break }
                    { $_ -eq 'GHS' } { "success"; break }
                    { $_ -eq 'JBOD' } { "success"; break }
                    { $_ -eq 'DHS' } { "success"; break }
                    { $_ -eq 'UGood' } { "success"; break }
                    default { "danger" }
                }

                $alldrives.Add([PSCustomObject]@{
                    Controller          = $controllertrimmed
                    Array               = $($physicaldrive.DG)
                    DriveNumber         = $($physicaldrive.DID)
                    Port                = $($physicaldrive.'EID:Slt')
                    Bay                 = $null
                    Status              = $($physicaldrive.State)
                    Reason              = $null
                    Size                = $($physicaldrive.Size)
                    Interface           = $($physicaldrive.Intf) + " " + $($physicaldrive.Med)
                    Serial              = ($driveObjects | Where-Object -Property DriveIdentifier -eq $($physicaldrive.'EID:Slt')).SerialNumber
                    Model               = $($physicaldrive.Model)
                    'Temp'              = $null
                    'Max Temp'          = $null
                    'Smart Status'      = $null
                    'Power On Hours'    = $null
                    'DriveLetter'       = $null
                    RowColour           = $RowColour
                })
            }

            $FailedVirtualDrives        = $virtualdrives | Where-Object { $_.Status -ne "Optl" }
            $FailedDrives               = $alldrives | Where-Object { $_.Status -ne "Onln" -and $_.Status -ne "GHS" -and $_.Status -ne "JBOD" -and $_.Status -ne "DHS" -and $_.Status -ne "UGood" }
            $MissingDrives              = $virtualdrivesgroup | Where-Object { $_.Status -eq "Msng" }

            if ($FailedDrives -or $MissingDrives) {
                $RAIDphysicalstatus = "Not Healthy"
            } else {
                $RAIDphysicalstatus = "Healthy"
            }

            if ($FailedVirtualDrives) {
                $RAIDStatus = "Not Healthy"
            } else {
                $RAIDStatus = "Healthy"
            }

            $lines = $ExecutepercCLICommandrebuildprogress -split "\r?\n"
            $lines | Where-Object { $_ -notmatch "Not in progress" } | ForEach-Object {
                if ($_ -match "(\d+)\s+In progress\s+(.+)$") {
                    $rebuildpercentage = $matches[1] + " %"
                    $estimatedTimeLeft = $matches[2]
                }
            }

            $raidarraydetails.Add([PSCustomObject]@{
                Controller          = $controllertrimmed
                Model               = $PERCcontrollermodel
                Serial              = $PERCcontrollerserial
                Firmware            = $PERCcontrollerfirmware
                Driver              = $PERCcontrollerdriver
                'Rebuild Status'    = if ($rebuildpercentage) { $rebuildpercentage } else { "Not Rebuilding" }
                'Rebuild Remaining' = if ($estimatedTimeLeft) { $estimatedTimeLeft } else { "Not Rebuilding" }
                ReadAhead           = $virtualdrives.ReadAhead | Select-Object -First 1
                WriteBack           = $virtualdrives.WriteBack | Select-Object -First 1
                VirtualStatus       = $RAIDStatus
                PhysicalStatus      = $RAIDphysicalstatus
                RowColour           = if (($RAIDStatus -eq 'Not Healthy') -or ($RAIDphysicalstatus -eq 'Not Healthy')) { "danger" } elseif ($rebuildpercentage) { 'warning' } else { "success" }
            })
        }
    } catch {
        $ScriptError = "percCLI Command has Failed: $($_.Exception.Message)"
        exit
    }

    return $raidarraydetails, $alldrives, $virtualdrives, $FailedDrives, $FailedVirtualDrives, $MissingDrives
}
