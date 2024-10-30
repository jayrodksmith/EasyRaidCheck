function Get-RaidControllerVROC {
    [CmdletBinding()]
    param (
        [string]$vrocCLILocation = 'C:\ProgramData\EasyRaidCheck\VROC\IntelVROCCli.exe'
    )

    Get-RaidControllerVROCPreReq -vrocLocation $vrocCLILocation

    $alldrives              = New-Object System.Collections.Generic.List[Object]
    $missingdrives          = New-Object System.Collections.Generic.List[Object]
    $failedvirtualdrives    = New-Object System.Collections.Generic.List[Object]
    $faileddrives           = New-Object System.Collections.Generic.List[Object]
    $raidarraydetails       = New-Object System.Collections.Generic.List[Object]
    $virtualdrivesgroup     = New-Object System.Collections.Generic.List[Object]
    $virtualdrives          = New-Object System.Collections.Generic.List[Object]

    # Get all Device and Volume Information
    try {
        # Run command for DISK INFORMATION (-d) to get all devices
        $diskOutput = & $vrocCLILocation -I -d
        $diskLines = $diskOutput -split "`r?`n"

        # Initialize an array for device objects (all disks)
        $deviceInfoList = @()
        $currentDeviceInfo = @{ }

        # Parse DISK INFORMATION into objects
        foreach ($line in $diskLines) {
            if ($line -match "^ID:\s+(.+)") {
                # Each "ID" starts a new device entry
                if ($currentDeviceInfo.Count -gt 0) { $deviceInfoList += [PSCustomObject]$currentDeviceInfo }
                $currentDeviceInfo = @{ "ID" = $matches[1].Trim(); "VolumeName" = $null } # Initialize VolumeName as null
            } elseif ($line -match "^(.+?):\s+(.+)$") {
                $currentDeviceInfo[$matches[1].Trim()] = $matches[2].Trim()
            }
        }
        # Add the last device entry
        if ($currentDeviceInfo.Count -gt 0) { $deviceInfoList += [PSCustomObject]$currentDeviceInfo }

        # Run command for VOLUME INFORMATION (-v) to get volume and associated disks
        $volumeOutput = & $vrocCLILocation -I -v
        $volumeLines = $volumeOutput -split "`r?`n"

        # Initialize variables for volume information, disk parsing within volumes, and array for all volumes
        $volumeObjs = @()
        $volumeInfo = @{ }
        $currentVolumeDisks = @()
        $isDiskSection = $false
        $volumeName = ""

        foreach ($line in $volumeLines) {
            if ($line -match "^--VOLUME INFORMATION--") {
                # Start of Volume Information section; reset for new volume
                if ($volumeInfo.Count -gt 0) {
                    # Add the previous volume object to volume list
                    $volumeInfo["Disks"] = $currentVolumeDisks
                    $volumeObjs += [PSCustomObject]$volumeInfo
                }
                $volumeInfo = @{}
                $currentVolumeDisks = @()
                $isDiskSection = $false
            }
            elseif ($line -match "^Name:\s+(.+)$") {
                # Capture the volume name for current volume
                $volumeName = $matches[1].Trim()
                $volumeInfo["Name"] = $volumeName
            }
            elseif ($line -match "^--DISKS IN VOLUME") {
                # Start of Disks section within the current volume
                $isDiskSection = $true
            }
            elseif ($line -match "^(.+?):\s+(.+)$") {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim()
                
                if ($isDiskSection) {
                    # Disk information within a volume
                    if ($key -eq "ID") {
                        # Find matching disk in device list and add volume name
                        $disk = $deviceInfoList | Where-Object { $_.ID -eq $value }
                        if ($disk) {
                            $disk.VolumeName = $volumeName
                            # Add disk to the current volume's disk list
                            $currentVolumeDisks += $disk
                        }
                    }
                } else {
                    # General Volume information
                    $volumeInfo[$key] = $value
                }
            }
        }
    
        # Add the last volume to the volume list
        if ($volumeInfo.Count -gt 0) {
            $volumeInfo["Disks"] = $currentVolumeDisks
            $volumeObjs += [PSCustomObject]$volumeInfo
        }
        
        foreach ($physicaldrive in $deviceInfoList) {
            $RowColour = switch ($($physicaldrive.State)) {
                { $_ -eq 'Normal' } { "success"; break }
                default { "danger" }
            }
            function Convert-GBtoTB {
                param (
                    [string]$sizeString
                )
            
                # Check if the size string contains "GB"
                if ($sizeString -match "([0-9.]+)\s*GB") {
                    # Extract the numeric part and convert it to TB
                    $sizeInGB = [float]$matches[1]
                    $sizeInTB = $sizeInGB / 1024
                    return "{0:N2} TB" -f $sizeInTB
                }
                else {
                    # Return the original size if it's not in GB
                    return $sizeString
                }
            }
            
            $alldrives.Add([PSCustomObject]@{
                Controller          = "VROC"
                Array               = $($physicaldrive.'VolumeName')
                DriveNumber         = $($physicaldrive.ID)
                Port                = $($physicaldrive.'Root Port Offset')
                Bay                 = $null
                Status              = $($physicaldrive.State)
                Reason              = $null
                Size                = Convert-GBtoTB -sizeString $($physicaldrive.Size)
                Interface           = $($physicaldrive.'Disk Type')
                Serial              = $($physicaldrive.'Serial Number')
                Model               = $($physicaldrive.Model)
                'Temp'              = $null
                'Max Temp'          = $null
                'Smart Status'      = $null
                'Power On Hours'    = $null
                'DriveLetter'       = $null
                RowColour           = $RowColour
            })
        }
            # Get Virtual Drive Status
            foreach ($VirtualDrive in $volumeObjs) {
                $RowColour = switch ($($VirtualDrive.State)) {
                    { $_ -eq 'Normal' } { "success"; break }
                    default { "danger" }
                }
                $virtualdrives.Add([PSCustomObject]@{
                    Controller      = 'VROC'
                    Array           = $($VirtualDrive.'Name')
                    Type            = "RAID" + $($VirtualDrive.'Raid Level')
                    Status          = $($VirtualDrive.'State')
                    Access          = $null
                    Cache           = $($VirtualDrive.'Cache Policy')
                    ReadAhead       = $null
                    WriteBack       = $null
                    Size            = $($VirtualDrive.'Size')
                    Name            = $($VirtualDrive.'Name')
                    RowColour       = $RowColour
                })
            }
    } catch {
        $ScriptError = "vrocCLI Command has Failed: $($_.Exception.Message)"
        # exit
    }

    try {
        # Run command to capture the full controller information output
        $controllerOutput = & $vrocCLILocation -I -c
        $controllerLines = $controllerOutput -split "`r?`n"

        # Initialize hashtable for controller information
        $controllerInfo = @{}
        $isControllerSection = $false

        # Parse only the Controller Information section
        foreach ($line in $controllerLines) {
            if ($line -match "^--CONTROLLER INFORMATION--") {
                # Start of Controller Information section
                $isControllerSection = $true
                continue
            }
            elseif ($line -match "^--ARRAY INFORMATION--") {
                # End of Controller Information section
                break
            }

            # Capture key-value pairs if in the Controller Information section
            if ($isControllerSection -and $line -match "^(.+?):\s+(.+)$") {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim()
                $controllerInfo[$key] = $value
            }
        }

        $FailedVirtualDrives        = $virtualdrives | Where-Object { $_.Status -ne "Normal" }
        $FailedDrives               = $alldrives | Where-Object { $_.Status -ne "Normal" }
        $MissingDrives              = $alldrives | Where-Object { $_.Status -eq "Msng" }

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

        $raidarraydetails.Add([PSCustomObject]@{
            Controller          = 'VROC'
            Model               = $($controllerInfo.Name)
            Serial              = $null
            Firmware            = $null
            Driver              = $null
            'Rebuild Status'    = $null
            'Rebuild Remaining' = $null
            ReadAhead           = $null
            WriteBack           = $null
            VirtualStatus       = $RAIDStatus
            PhysicalStatus      = $RAIDphysicalstatus
            RowColour           = if (($RAIDStatus -eq 'Not Healthy') -or ($RAIDphysicalstatus -eq 'Not Healthy')) { "danger" } elseif ($rebuildpercentage) { 'warning' } else { "success" }
        })
    } catch {
        $ScriptError = "vrocCLI Command has Failed: $($_.Exception.Message)"
        # exit
    }
    return $raidarraydetails, $alldrives, $virtualdrives, $FailedDrives, $FailedVirtualDrives, $MissingDrives
}
