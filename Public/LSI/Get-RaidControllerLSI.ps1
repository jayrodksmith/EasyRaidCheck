function Get-RaidControllerLSI{
    [CmdletBinding()]
    param (
        [string]$StorCLILocation = 'C:\temp\Intel_StorCLI_007.1907.0000.0000\Unified_storcli_all_os\Windows\storcli64.exe',
        [string]$StorCliCommandvirtualdrive = "/c0 /vall show j",
        [string]$StorCliCommandvirtualdrivegroup = "/c0 /dall show j",
        [string]$StorCliCommandphysical = "/c0 /eall /sall show j",
        [string]$StorCliCommandphysicalall = "/c0 /eall /sall show all",
        [string]$controllerName = "Unknown"
    )
    
    Get-RaidControllerLSIPreReq
    try {
        $ExecuteStoreCLIvirtualdrive = & $StorCLILocation $StorCliCommandvirtualdrive | out-string
        $ArrayStorCLIvirtualdrive = ConvertFrom-Json $ExecuteStoreCLIvirtualdrive
        $ExecuteStoreCLIvirtualdrivegroup = & $StorCLILocation $StorCliCommandvirtualdrivegroup | out-string
        $ArrayStorCLIvirtualdrivegroup = ConvertFrom-Json $ExecuteStoreCLIvirtualdrivegroup
        } catch {
            $ScriptError = "StorCli Command has Failed: $($_.Exception.Message)"
            exit
        }
    #Wipe Raid Status
    $RAIDStatus = ""
    $PhysicalStatus = ""
    # Get Virtual Drive Status + Physical
    $virtualdrivesgroup = New-Object System.Collections.Generic.List[Object]
    foreach($VirtualDrivegroup in $ArrayStorCLIvirtualdrivegroup.Controllers.'response data'.'response data'.'TOPOLOGY'){
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
    foreach($VirtualDrive in $ArrayStorCLIvirtualdrive.Controllers.'response data'.'Virtual Drives'){
        $RowColour = switch ($($VirtualDrive.State)) {
            { $_ -eq 'Optl' } { "success"; break }
            default { "danger" } 
        }
        $virtualdrives.Add([PSCustomObject]@{
            Array               = $($VirtualDrive.'DG/VD')
            Type                = $($VirtualDrive.'TYPE')
            Status              = $($VirtualDrive.'State')
            Access              = $($VirtualDrive.'Access')
            Cache               = $($VirtualDrive.'Cache')
            Size                = $($VirtualDrive.'Size')
            Name                = $($VirtualDrive.'Name')
            RowColour           = $RowColour
        })    
    }
    try {
        $ExecuteStoreCLIphysical = & $StorCLILocation $StorCliCommandphysical | out-string
        $ArrayStorCLIphysical = ConvertFrom-Json $ExecuteStoreCLIphysical
        $ExecuteStoreCLIphysicalall = & $StorCLILocation $StorCliCommandphysicalall | out-string
        # Convert the multiline string to an array of strings by splitting on new lines
        $driveEntries = $ExecuteStoreCLIphysicalall -split [System.Environment]::NewLine

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
            $ScriptError = "StorCli Command has Failed: $($_.Exception.Message)"
            exit
    }

    # Get All Drives
    $AllDrives = New-Object System.Collections.Generic.List[Object]
    foreach($physicaldrive in $ArrayStorCLIphysical.Controllers.'Response data'.'Drive Information'){
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
    $raidarraydetails = New-Object System.Collections.Generic.List[Object]
    $raidarraydetails.Add([PSCustomObject]@{
        Controller              = $controllerName
        VirtualStatus           = $RAIDStatus
        PhysicalStatus          = $RAIDphysicalstatus
    })
    
    return $raidarraydetails, $AllDrives, $FailedDrives, $FailedVirtualDrives, $MissingDrives
}