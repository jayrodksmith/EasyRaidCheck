function Get-RaidControllerHP{
    [CmdletBinding()]
    param (
        [string]$StorCLILocation = 'C:\temp\Intel_StorCLI_007.1907.0000.0000\Unified_storcli_all_os\Windows\storcli64.exe',
        [string]$StorCliCommandvirtualdrive = "/c0 /vall show j",
        [string]$StorCliCommandvirtualdrivegroup = "/c0 /dall show j",
        [string]$StorCliCommandphysical = "/c0 /eall /sall show j",
        [string]$StorCliCommandphysicalall = "/c0 /eall /sall show all"
    )
    
    Get-RaidControllerLSIPreReq
    try {
        $ExecuteStoreCLIvirtualdrive = & 'C:\temp\Intel_StorCLI_007.1907.0000.0000\Unified_storcli_all_os\Windows\storcli64.exe' $StorCliCommandvirtualdrive | out-string
        $ArrayStorCLIvirtualdrive = ConvertFrom-Json $ExecuteStoreCLIvirtualdrive
        $ExecuteStoreCLIvirtualdrivegroup = & 'C:\temp\Intel_StorCLI_007.1907.0000.0000\Unified_storcli_all_os\Windows\storcli64.exe' $StorCliCommandvirtualdrivegroup | out-string
        $ArrayStorCLIvirtualdrivegroup = ConvertFrom-Json $ExecuteStoreCLIvirtualdrivegroup
        } catch {
            $ScriptError = "StorCli Command has Failed: $($_.Exception.Message)"
            exit
        }
    #Wipe Raid Status
    $RAIDStatus = ""
    $PhysicalStatus = ""
    foreach($VirtualDrivegroup in $ArrayStorCLIvirtualdrivegroup.Controllers.'response data'.'response data'.'TOPOLOGY'){
        if($($VirtualDrivegroup.state) -eq "Msng"){
            $PhysicalStatus += "Slot: $($VirtualDrivegroup.'Row') With Size $($VirtualDrivegroup.'Size') is Missing"
            }
    }
    foreach($VirtualDrive in $ArrayStorCLIvirtualdrive.Controllers.'response data'.'Virtual Drives'){
        if($($VirtualDrive.state) -ne "Optl"){
            $RAIDStatus += "Virtual Drive: $($VirtualDrive.'DG/VD') With Size $($VirtualDrive.'Size') is $($VirtualDrive.State)"
        }
    }
    try {
        $ExecuteStoreCLIphysical = C:\temp\Intel_StorCLI_007.1907.0000.0000\Unified_storcli_all_os\Windows\storcli64.exe $StorCliCommandphysical | out-string
        $ArrayStorCLIphysical = ConvertFrom-Json $ExecuteStoreCLIphysical
        $ExecuteStoreCLIphysicalall = C:\temp\Intel_StorCLI_007.1907.0000.0000\Unified_storcli_all_os\Windows\storcli64.exe $StorCliCommandphysicalall | out-string
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
    # Get Failed Drives
    foreach($physicaldrive in $ArrayStorCLIphysical.Controllers.'Response data'.'Drive Information'){
        if($($physicaldrive.state) -ne "Onln"-and $($physicaldrive.state) -ne "GHS" -and $($physicaldrive.state) -ne "JBOD" -and $($physicaldrive.state) -ne "DHS" -and $($physicaldrive.state) -ne "UGood"){
            $PhysicalStatus += “$($physicaldrive.Model) With Disk ID $($physicaldrive.DID) is $($physicaldrive.State)"
        }
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
            Array = $($physicaldrive.DG)
            DriveNumber = $($physicaldrive.DID)
            Port = $($physicaldrive.'EID:Slt')
            Bay = $null
            Status = $($physicaldrive.State)
            Reason = $null
            Size = $($physicaldrive.Size)
            Interface = $($physicaldrive.Intf) +" "+ $($physicaldrive.Med)
            Serial = ($driveObjects  |  Where-Object -Property DriveIdentifier -eq $($physicaldrive.'EID:Slt')).SerialNumber
            Model = $($physicaldrive.Model)
            'Temp' = $null
            'Max Temp' = $null
            RowColour = $RowColour
        })    
    }
    
    $FailedDrives = $AllDrives | Where-Object { $_.Status -ne "Onln" -and $_.Status -ne "GHS" -and $_.Status -ne "JBOD" -and $_.Status -ne "DHS" -and $_.Status -ne "UGood"}
    
    if($FailedDrives) {
        Write-Output "Failed Drive Details"
        $FailedDrives
        $RAIDphysicalstatus = "Not Healthy"
    }
    
    ## Get Details of failed drive  
    if (!$RAIDStatus) {
        $RAIDStatus = "Healthy"
    }
    if ($null -eq $PhysicalStatus) {
        $PhysicalStatus = "Healthy"
    }
    if (!$ScriptError) {
        $ScriptError = "Healthy"
    }
    if ($RAIDStatus -ne "Healthy"){
    Write-Host "Drive Failure"
    Write-Host "$RAIDStatus"
    }
    if ($PhysicalStatus -ne "Healthy"){
    Write-Host "$PhysicalStatus"
    }
    
    $raidarraydetails = [pscustomobject][ordered]@{
        Controller = $controllerName
        VirtualStatus = $RAIDStatus
        PhysicalStatus = $RAIDphysicalstatus
    }
    $raidarraydetails = $raidarraydetails | Format-List | Out-String

    return $raidarraydetails, $faileddrives, $AllDrives
}