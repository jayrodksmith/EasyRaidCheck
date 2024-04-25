function Get-RaidControllerHP{
    [CmdletBinding()]
    param (
        [string]$hpCLIlocation = "",
        [string]$hpADUlocation = "",
        [string]$hpclireport = "C:\ProgramData\EasyRaidCheck\HP\HPReport.txt",
        [string]$controllerName = "Unknown"

    )
    
    Get-RaidControllerHPPreReq -hpLocationcli $hpCLIlocation -hpLocationadu $hpADUlocation

    $hpraidstatus = & $hpCLIlocation ctrl all show status | Out-String
    $hpraidstatus2 = & $hpADUlocation -adu -txt -f $hpclireport

    ######## Get HP Smart details Start
        $objects = @()
        $objects2 = @()

        # Initialize object variables
        $object = $null
        $object2 = $null
        Get-Content $hpclireport | ForEach-Object {
            $line = $_.Trim()
        
            # Check if the line contains the drive ID
            if ($line -match 'Physical Drive \(.*?\) (\d+I:\d+:\d+) : Workload Information') {
                # If previous object exists, add it to the list
                if ($object -ne $null) {
                    $objects += $object
                }
                
                # Create a new object for the current drive
                $driveId = $matches[1]
                $object = New-Object -TypeName PSObject
                $object | Add-Member -MemberType NoteProperty -Name DriveId -Value $driveId
                Write-Verbose "Matched Drive $driveId in smart loop"
            } elseif ($object -ne $null) {
                # Store each matched line into the object
                if ($line -match '^(Power-on Hours|Total LBA Read|Total LBA Written|Workload Rating \(TB/Yr\)|Month\(s\) of Operation|Total Bytes Read \(TB\)|Total Bytes Written \(TB\)|Total Combined Read/Write Bytes \(TB\)|Workload Rate \(TB/Month\)|Projected Rate \(TB/Year\)|SSD Usage Remaining \(%\))\s+(.*)$') {
                    $propertyName = $matches[1].Trim()
                    $propertyValue = $matches[2].Trim()
                    $object | Add-Member -MemberType NoteProperty -Name $propertyName -Value $propertyValue
                }
        
                # Check if all lines are stored, then add the object to the list
                if ($object.psobject.Properties.Count -eq 11) {
                    $objects += $object
                    
                    # Reset object for the next drive
                    $object = $null
                }
            }
        }
        # Add the last object to the list if it exists
        if ($object -ne $null) {
            $objects += $object
        }
        # Regular expression patterns for matching drive ID and properties
        $driveIdPattern = 'Physical Drive \(.*?\) (\d+I:\d+:\d+) : Monitor and Performance Statistics \(Since Factory\)'
        $propertyPattern = '^(Serial Number|Firmware Revision|Seek Errors|Read Errors Hard|Write Errors Hard|Media Failures|Hardware Errors|Spin Up Failures|Predictive Failure Errors)\s+(.*)$'

        Get-Content $hpclireport | ForEach-Object {
            $line = $_.Trim()

            # Check if the line contains the drive ID
            if ($line -match $driveIdPattern) {
                # If previous object exists, add it to the list
                if ($object2 -ne $null) {
                    $objects2 += $object2
                }
                
                # Create a new object for the current drive
                $driveId = $matches[1]
                $object2 = [PSCustomObject]@{ DriveId = $driveId }
            } elseif ($object2 -ne $null -and $line -match $propertyPattern) {
                # Store each matched line into the object
                $propertyName = $matches[1].Trim()
                $propertyValue = $matches[2].Trim()
                $object2 | Add-Member -MemberType NoteProperty -Name $propertyName -Value $propertyValue

                # If all properties are collected, add the object to the list
                if ($propertyName -eq 'Predictive Failure Errors') {
                    $objects2 += $object2
                    $object2 = $null  # Reset object2 for the next drive
                }
            }
        }
        $hpsmartdetails = foreach ($obj in $objects) {
            $matchingObject = $objects2 | Where-Object { $_.driveid -eq $obj.driveid }
        
            if ($matchingObject) {
                $mergedProperties = @{}
        
                $obj.PSObject.Properties | ForEach-Object {
                    $mergedProperties[$_.Name] = $_.Value
                }
        
                $matchingObject.PSObject.Properties | ForEach-Object {
                    $mergedProperties[$_.Name] = $_.Value
                }
        
                [PSCustomObject]$mergedProperties
            }
        }
    ######## Get HP Smart details End

    # Define the regex pattern to match "Slot X" where X is a number
    $pattern = "Slot (\d+)"

    # Find all matches of "Slot X" in the variable
    $slotmatches = [regex]::Matches($hpraidstatus, $pattern)
    $hpraidstatusslot_array = ""
    $hpraidstatusslot_pd = ""
    $hpraidstatusslot_ld = ""
    # Output each "Slot X" found as "slot=X"
    foreach ($match in $slotmatches) {
        $slotNumber = $match.Groups[1].Value
            #Write-Output "slot=$slotNumber"
            $hpraidstatusslot_array += & $hpCLIlocation ctrl slot=$slotNumber array all show status | Out-String
            $hpraidstatusslot_pd += & $hpCLIlocation ctrl slot=$slotNumber pd all show | Out-String
            $hpraidstatusslot_ld += & $hpCLIlocation ctrl slot=$slotNumber ld all show | Out-String
    }
    $PhysicalStatus = ""

    # Log all drives
    $PhysicalStatus = $hpraidstatusslot_pd
    $AllDrives = New-Object System.Collections.Generic.List[Object]
    $PhysicalStatus_drivenumbers = ($PhysicalStatus -split "`n" | Select-String -Pattern "physicaldrive" | ForEach-Object { [regex]::Match($_, '(\d+[A-Z]:\d+:\d+)').Value })
    foreach ($PhysicalStatus_drivenumber in $PhysicalStatus_drivenumbers) {
        Write-Verbose "Creating object for $PhysicalStatus_drivenumber"
        $hpraidstatusslot_pd_details = & $hpCLIlocation ctrl slot=$slotNumber pd "$PhysicalStatus_drivenumber" show detail | Out-String
        $ArrayLine = ($hpraidstatusslot_pd_details -split "`n" | Select-String -Pattern "Array")
        $Array = if ($ArrayLine) { $ArrayLine.Line.TrimStart().Split(" ", 2)[-1].Trim() } else { $null }

        $portLine = ($hpraidstatusslot_pd_details -split "`n" | Where-Object { $_ -notmatch "Shingled" } | Select-String -Pattern "Port:")
        $port = if ($portLine) { $portLine.Line.TrimStart().Split(":", 2)[-1].Trim() } else { $null }
        
        $bayLine = ($hpraidstatusslot_pd_details -split "`n" | Select-String -Pattern "Bay:")
        $bay = if ($bayLine) { $bayLine.Line.TrimStart().Split(":", 2)[-1].Trim() } else { $null }
        
        $statusLine = ($hpraidstatusslot_pd_details -split "`n" | Where-Object { $_ -notmatch "Authentication" } | Select-String -Pattern "Status:")
        $status = if ($statusLine) { $statusLine.Line.TrimStart().Split(":", 2)[-1].Trim() } else { $null }
        
        $reasonLine = ($hpraidstatusslot_pd_details -split "`n" | Select-String -Pattern "Last Failure Reason:")
        $reason = if ($reasonLine) { $reasonLine.Line.TrimStart().Split(":", 2)[-1].Trim() } else { "Healthy" }
        
        $sizeLine = ($hpraidstatusslot_pd_details -split "`n" | Where-Object { $_ -notmatch "Block" } | Select-String -Pattern "Size:")
        $size = if ($sizeLine) { $sizeLine.Line.TrimStart().Split(":", 2)[-1].Trim() } else { $null }
        
        $interfaceLine = ($hpraidstatusslot_pd_details -split "`n" | Select-String -Pattern "Interface Type:")
        $interface = if ($interfaceLine) { $interfaceLine.Line.TrimStart().Split(":", 2)[-1].Trim() } else { $null }
        
        $serialNumberLine = ($hpraidstatusslot_pd_details -split "`n" | Select-String -Pattern "Serial Number:")
        $serialNumber = if ($serialNumberLine) { $serialNumberLine.Line.TrimStart().Split(":", 2)[-1].Trim() } else { $null }
        
        $modelLine = ($hpraidstatusslot_pd_details -split "`n" | Select-String -Pattern "Model:")
        $model = if ($modelLine) { ($modelLine.Line.TrimStart() -replace '(\s)+', ' ').Split(":", 2)[-1].Trim() } else { $null }
        
        $MaximumtemperatureLine = ($hpraidstatusslot_pd_details -split "`n" | Select-String -Pattern "Maximum Temperature")
        $Maximumtemperature = if ($MaximumtemperatureLine) { $MaximumtemperatureLine.Line.TrimStart().Split(":", 2)[-1].Trim() } else { $null }

        $CurrenttemperatureLine = ($hpraidstatusslot_pd_details -split "`n" | Select-String -Pattern "Current Temperature")
        $Currenttemperature = if ($CurrenttemperatureLine) { $CurrenttemperatureLine.Line.TrimStart().Split(":", 2)[-1].Trim() } else { $null }
        # Set the row colour based on the size of the file
        $RowColour = switch ($status) {
                { $_ -eq 'OK' } { "success"; break }
                { $_ -ne 'OK' } { "danger"; break }
                default { "unknown" } 
        }
        $AllDrives.Add([PSCustomObject]@{
            Array                       = $Array
            DriveNumber                 = $PhysicalStatus_drivenumber
            Port                        = $port
            Bay                         = $bay
            Status                      = $status
            Reason                      = $reason
            Size                        = $size
            Interface                   = $interface
            Serial                      = $serialNumber
            Model                       = $model
            'Temp'                      = $Currenttemperature
            'Max Temp'                  = $Maximumtemperature
            'Smart Status'              = $null
            'Power On Hours'            = ( $hpsmartdetails | Where-Object -Property 'Serial Number' -eq $serialNumber | Select-Object -ExpandProperty 'Power-on Hours' )
            RowColour                   = $RowColour
        })
    }
    if ($hpraidstatus -like "*Failure*" -or $hpraidstatus -like "*Failed*" -or $hpraidstatus -like "*Error*" -or $hpraidstatusslot_array -like "*Failed*" -or $hpraidstatusslot_pd -like "*Failed*") {
        $RAIDStatus = "Not Healthy"
    }
    $FailedDrives = $AllDrives | Where-Object -Property Status -eq 'Failed'
    if($FailedDrives) {
        $RAIDphysicalstatus = "Not Healthy"
    } else {
        $RAIDphysicalstatus = "Healthy"
    }
    
    ## Get Details of failed drive  
    if (!$RAIDStatus) {
        $RAIDStatus = "Healthy"
    }
    
    $raidarraydetails = New-Object System.Collections.Generic.List[Object]
    $raidarraydetails.Add([PSCustomObject]@{
        Controller              = $controllerName
        VirtualStatus           = $RAIDStatus
        PhysicalStatus          = $RAIDphysicalstatus
    })

    return $raidarraydetails, $AllDrives, $faileddrives
}