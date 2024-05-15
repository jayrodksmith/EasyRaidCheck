function Get-RaidControllerPERC{
    [CmdletBinding()]
    param (
        [string]$PercCLILocation = 'C:\ProgramData\EasyRaidCheck\LSI\perccli64.exe',
        [string]$PercCLICommandvirtualdrive = "/c0 /vall show j",
        [string]$PercCLICommandvirtualdrivegroup = "/c0 /dall show j",
        [string]$PercCLICommandphysical = "/c0 /eall /sall show j",
        [string]$PercCLICommandphysicalall = "/c0 /eall /sall show all",
        [string]$PercCLICommandbasicinfo = "show all",
        [string]$PercCLICommandbasicinfo2 = "/c0 show",
        [string]$PercCLICommandrebuildprogress = "/c0 /eall /sall show rebuild",
        [string]$controllerName = "Unknown"
    )
    
    Get-RaidControllerLSIPreReq -lsiCLILocation $PercCLILocation
    try {
        $ExecutePercCLIvirtualdrive             = & $PercCLILocation $PercCLICommandvirtualdrive | out-string
        $ArrayPercCLIvirtualdrive               = ConvertFrom-Json $ExecutePercCLIvirtualdrive
        $ExecutePercCLIvirtualdrivegroup        = & $PercCLILocation $PercCLICommandvirtualdrivegroup | out-string
        $ArrayPercCLIvirtualdrivegroup          = ConvertFrom-Json $ExecutePercCLIvirtualdrivegroup
        $ExecutePercCLICommandbasicinfo         = & $PercCLILocation $PercCLICommandbasicinfo
        $ExecutePercCLICommandbasicinfo2        = & $PercCLILocation $PercCLICommandbasicinfo2
        $ExecutePercCLICommandrebuildprogress   = & $PercCLILocation $PercCLICommandrebuildprogress
        } catch {
            $ScriptError = "PercCLI Command has Failed: $($_.Exception.Message)"
            exit
        }
    # Get number of controllers
    $PERCcontrollercount     = $ExecutePercCLICommandbasicinfo  | Select-String -Pattern "Number of Controllers\s*=\s*(\d+)" | ForEach-Object { $_.Matches.Groups[1].Value }
    $PERCcontrollermodel     = $ExecutePercCLICommandbasicinfo2 | Select-String -Pattern "Product Name\s*=\s*(.*)" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() }
    $PERCcontrollerserial    = $ExecutePercCLICommandbasicinfo2 | Select-String -Pattern "Serial Number\s*=\s*(.*)" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() }
    $PERCcontrollerfirmware  = $ExecutePercCLICommandbasicinfo2 | Select-String -Pattern "FW Version\s*=\s*(.*)" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() }
    $PERCcontrollerdriver    = $ExecutePercCLICommandbasicinfo2 | Select-String -Pattern "Driver Version\s*=\s*(.*)" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() }

    #Wipe Raid Status
    $RAIDStatus = ""
    $PhysicalStatus = ""
    # Get Virtual Drive Status + Physical
    $virtualdrivesgroup = New-Object System.Collections.Generic.List[Object]
    foreach($VirtualDrivegroup in $ArrayPercCLIvirtualdrivegroup.Controllers.'response data'.'response data'.'TOPOLOGY'){
        $RowColour = switch ($($VirtualDrivegroup.State)) {
            { $_ -eq 'Onln' } { "success"; break }
            { $_ -eq 'Optl' } { "success"; break }
            default { "danger" } 
        }
        $virtualdrivesgroup.Add([PSCustomObject]@{
            DriveGroup          = $($VirtualDrivegroup.'DG')
            Array               = $($VirtualDrivegroup.'Arr')
            Row                 = $($VirtualDrivegroup.'Row')
            'EID:Slot'          = $($VirtualDrivegroup.'EID:Slot')
            DID                 = $($VirtualDrivegroup.'DID')
            Type                = $($VirtualDrivegroup.'Type')
            Status              = $($VirtualDrivegroup.'State')
            Size                = $($VirtualDrivegroup.'Size')
            RowColour           = $RowColour
        })
    }

    # Get Virtual Drive Status
    $virtualdrives = New-Object System.Collections.Generic.List[Object]
    foreach($VirtualDrive in $ArrayPercCLIvirtualdrive.Controllers.'response data'.'Virtual Drives'){
        $RowColour = switch ($($VirtualDrive.State)) {
            { $_ -eq 'Optl' } { "success"; break }
            default { "danger" } 
        }
        if ($($VirtualDrive.'Cache')-eq 'RWBD' ) {
            $ReadAhead = $true
            $WriteBack = $true
        }
        if ($($VirtualDrive.'Cache')-eq 'RAWBD' ) {
            $ReadAhead = $true
            $WriteBack = $true
        }
        if ($($VirtualDrive.'Cache')-eq 'NRWTD' ) {
            $ReadAhead = $false
            $WriteBack = $false
        }
        if ($($VirtualDrive.'Cache')-eq 'RWTD' ) {
            $ReadAhead = $true
            $WriteBack = $true
        }
        if ($($VirtualDrive.'Cache')-eq 'NRWBD' ) {
            $ReadAhead = $false
            $WriteBack = $true
        }
        if ($($VirtualDrive.'Cache')-eq 'NRAWBD' ) {
            $ReadAhead = $false
            $WriteBack = $true
        }
        $virtualdrives.Add([PSCustomObject]@{
            Array               = $($VirtualDrive.'DG/VD')
            Type                = $($VirtualDrive.'TYPE')
            Status              = $($VirtualDrive.'State')
            Access              = $($VirtualDrive.'Access')
            Cache               = $($VirtualDrive.'Cache')
            ReadAhead           = $ReadAhead
            WriteBack           = $WriteBack
            Size                = $($VirtualDrive.'Size')
            Name                = $($VirtualDrive.'Name')
            RowColour           = $RowColour
        })    
    }
    try {
        $ExecutePercCLIphysical = & $PercCLILocation $PercCLICommandphysical | out-string
        $ArrayPercCLIphysical = ConvertFrom-Json $ExecutePercCLIphysical
        $ExecutePercCLIphysicalall = & $PercCLILocation $PercCLICommandphysicalall | out-string
        # Convert the multiline string to an array of strings by splitting on new lines
        $driveEntries = $ExecutePercCLIphysicalall -split [System.Environment]::NewLine

        # Initialize an empty array to store drive objects
        $driveObjects = @()

        # Loop through each line in the array
        foreach ($line in $driveEntries) {
            # If the line starts with "Drive /c0/e", it indicates a new drive entry
            if ($line -match "^Drive /c0/e(\d+)/s(\d+)") {
                # Extract the drive identifier and rename it
                $driveIdentifier = "$($Matches[1]):$($Matches[2])"
            }
            # If the line starts with "SN =", it indicates a serial number
            elseif ($line -match "^SN =") {
                # Add the serial number to the hashtable using the current drive identifier as the key
                $serialNumber = $line -replace "SN = ", ""
                # Remove white spaces from the serial number
                $serialNumber = $serialNumber -replace "\s", ""
                
                # Create a custom object for the drive
                $driveObject = [PSCustomObject]@{
                    DriveIdentifier = $driveIdentifier
                    SerialNumber = $serialNumber
                }
                
                # Add the drive object to the array
                $driveObjects += $driveObject
            }
        }
    } catch {
            $ScriptError = "PercCLI Command has Failed: $($_.Exception.Message)"
            exit
    }

    # Get All Drives
    $AllDrives = New-Object System.Collections.Generic.List[Object]
    foreach($physicaldrive in $ArrayPercCLIphysical.Controllers.'Response data'.'Drive Information'){
        $RowColour = switch ($($physicaldrive.State)) {
            { $_ -eq 'Onln' } { "success"; break }
            { $_ -eq 'GHS' } { "success"; break }
            { $_ -eq 'JBOD' } { "success"; break }
            { $_ -eq 'DHS' } { "success"; break }
            { $_ -eq 'UGood' } { "success"; break }
            default { "danger" } 
        }
        $AllDrives.Add([PSCustomObject]@{
            Array               = $($physicaldrive.DG)
            DriveNumber         = $($physicaldrive.DID)
            Port                = $($physicaldrive.'EID:Slt')
            Bay                 = $null
            Status              = $($physicaldrive.State)
            Reason              = $null
            Size                = $($physicaldrive.Size)
            Interface           = $($physicaldrive.Intf) +" "+ $($physicaldrive.Med)
            Serial              = ($driveObjects  |  Where-Object -Property DriveIdentifier -eq $($physicaldrive.'EID:Slt')).SerialNumber
            Model               = $($physicaldrive.Model)
            'Temp'              = $null
            'Max Temp'          = $null
            'Smart Status'      = $null
            'Power On Hours'    = $null
            RowColour           = $RowColour
        })    
    }

    $FailedVirtualDrives        = $virtualdrives | Where-Object { $_.Status -ne "Optl"}
    $FailedDrives               = $AllDrives | Where-Object { $_.Status -ne "Onln" -and $_.Status -ne "GHS" -and $_.Status -ne "JBOD" -and $_.Status -ne "DHS" -and $_.Status -ne "UGood"}
    $MissingDrives              = $virtualdrivesgroup | Where-Object { $_.Status -eq "Msng"}
    
    if($FailedDrives -or $MissingDrives) {
        $RAIDphysicalstatus     = "Not Healthy"
    }else {
        $RAIDphysicalstatus     = "Healthy"
    }

    if ($FailedVirtualDrives) {
        $RAIDStatus             = "Not Healthy"
    } else {
        $RAIDStatus             = "Healthy"
    }
    # Split the text by line breaks
    $lines = $ExecutePercCLICommandrebuildprogress -split "\r?\n"
    # Extract progress and estimated time left from relevant lines
    $lines | Where-Object {$_ -notmatch "Not in progress"} | ForEach-Object {
        if ($_ -match "(\d+)\s+In progress\s+(.+)$") {
            $rebuildpercentage = $matches[1] + " %"
            $estimatedTimeLeft = $matches[2]
        }
    }

    $raidarraydetails = New-Object System.Collections.Generic.List[Object]
    $raidarraydetails.Add([PSCustomObject]@{
        Controller              = $PERCcontrollermodel
        ControllerCount         = $PERCcontrollercount
        'Rebuild Status'        = if($rebuildpercentage -ne ""){$rebuildpercentage}else{"Not Rebuilding"}
        'Rebuild Remaining'     = if($estimatedTimeLeft -ne ""){$estimatedTimeLeft}else{"Not Rebuilding"}
        ReadAhead               = $virtualdrives.ReadAhead | Select-Object -First 1
        WriteBack               = $virtualdrives.WriteBack | Select-Object -First 1
        VirtualStatus           = $RAIDStatus
        PhysicalStatus          = $RAIDphysicalstatus
        RowColour               = if (($RAIDStatus -eq 'Not Healthy') -or ($RAIDphysicalstatus -eq 'Not Healthy')) {"danger"}elseif ($rebuildpercentage -ne "") {'warning'}else{"success"}
    })
    
    return $raidarraydetails, $AllDrives, $virtualdrives, $FailedDrives, $FailedVirtualDrives, $MissingDrives
}