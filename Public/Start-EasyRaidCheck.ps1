function Start-EasyRaidCheck{
    [CmdletBinding()]
    param (
        # RMM Mode
        [string]$RMM                        = 'NinjaOne',
        # Ninja Custom Fields
        [string]$ninjafieldWYSIWYGdrives    = 'raidtablephysical',          # WYSIWYG field for Ninja
        [string]$ninjafieldWYSIWYGvirtual   = 'raidtablevirtual',           # WYSIWYG field for Ninja
        [string]$ninjafieldWYSIWYGstatus    = 'raidtablestatus',            # WYSIWYG field for Ninja
        [string]$ninjafieldraidarraystatus  = 'raidarraystatus',            # Text field for Ninja
        [string]$ninjafieldraidarraydetails = 'raidarraydetails',           # Text field for Ninja
        # Ninja Exit Code
        [int]$ninjaexitcodefailure          = '999',                        # Set this in your condition script result code
        # LSI Details
        [string]$storecli64                 = 'C:\ProgramData\EasyRaidCheck\LSI\storcli64.exe',     # Will download from intel if missing
        # HP Details
        [string]$ssacli                     = 'C:\ProgramData\EasyRaidCheck\HP\ssacli.exe',         # Will download from HP if missing
        [string]$ssaducli                   = 'C:\ProgramData\EasyRaidCheck\HP\ssaducli.exe',       # Will download from HP if missing
        # PERC Details
        [string]$perccli64                  = 'C:\ProgramData\EasyRaidCheck\Dell\perccli64.exe',   # Will download from my github if missing
        # CrystalDiskInfo Details
        [boolean]$Smartinfo                 = $true ,                                               # This will download CrystalDiskInfo if missing
        $DiskInfo64                         = "C:\ProgramData\EasyRaidCheck\Crystaldiskinfo\DiskInfo64.exe"

    )
    # Determine if the system is virtual
    $IsVirtual = @(Get-CimInstance -ClassName Win32_ComputerSystem | Where-Object { $_.Model -eq 'VMware Virtual Platform' -or $_.Model -eq 'Virtual Machine' }).Count -gt 0
    if($IsVirtual){
        return "Not Running because Virtual Machine"
    }
    $supportedcontrollers, $controllers = Get-RaidControllers

    if ($supportedcontrollers.'Controller Type' -match "LSI"){
        # LSI
        $raidarraydetails, $AllDrives, $virtualdrives, $FailedDrives, $FailedVirtualDrives, $MissingDrives  = Get-RaidControllerLSI -StorCLILocation $storecli64 -ControllerName ($($supportedcontrollers.'Controller Name') | Select-object -first 1)

    } elseif ($supportedcontrollers.'Controller Type' -match "HP"){
        # HP
        $raidarraydetails, $AllDrives, $faileddrives                                        = Get-RaidControllerHP -hpCLIlocation $ssacli -hpADUlocation $ssaducli -ControllerName ($($supportedcontrollers.'Controller Name') | Select-object -first 1)
    } elseif ($supportedcontrollers.'Controller Type' -match "PERC"){
        # HP
        $raidarraydetails, $AllDrives, $faileddrives                                        = Get-RaidControllerPERC -percCLILocation $perccli64 -ControllerName ($($supportedcontrollers.'Controller Name') | Select-object -first 1)
    } else {
        Write-Output "No Supported Controllers"
        $supported = $false
        $raidarraydetails = New-Object System.Collections.Generic.List[Object]
        $raidarraydetails.Add([PSCustomObject]@{
            Supported          = $false
        })

    }
    # Retrieve Smart Details using CrystalDiskInfo if set to true
    if($Smartinfo -eq $true){
        $smartalldrives, $smartFailedDrives                                                 = Get-SMARTInfo -CDIPath $DiskInfo64 
        # Check existing results and merge results if found.
        if ($supported -ne $false){
            foreach ($drive in $alldrives) {
                $serial = $($drive.Serial)
                $smartDrive = $smartalldrives | Where-Object { $_.'Serial Number' -match $serial }
            
                if ($smartDrive) {
                    # Merge existing fields from $smartalldrives into $alldrives and set danger flag if required
                    $drive.'Smart Status' = $($smartDrive.'Health Status')
                    $drive.'Power On Hours' = $($smartDrive.'Power On Hours')
                    if($null -eq $drive.'Temp'){
                        $drive.'Temp' = [regex]::Match($($smartDrive.'Temperature'), '^(\d+) C').Groups[1].Value
                    }
                    $percentage = [regex]::Match($drive.'Smart Status', '\((\d+)\s*%\)').Groups[1].Value
                    if($drive.'Smart Status' -notmatch '\bGood\b' -and $null -ne $drive.'Smart Status' -and $drive.'Smart Status' -notmatch '\bUnknown\b'){
                        $drive.'RowColour' = 'danger'
                    }
                }
            }
        } else {
                $AllDrives = $smartalldrives
                $faileddrives = $smartFailedDrives
        }
    }
    # Write Values to Ninja
    if($RMM -eq 'Ninjaone'){
        Get-FieldsNinjaRMM -fieldWYSIWYGdrives $ninjafieldWYSIWYGdrives -fieldWYSIWYGvirtual $ninjafieldWYSIWYGvirtual -fieldWYSIWYGstatus $ninjafieldWYSIWYGstatus -fieldraidarraystatus $ninjafieldraidarraystatus -fieldraidarraydetails $ninjafieldraidarraydetails
        Write-ResultNinjaRMM -fieldWYSIWYGdrives $ninjafieldWYSIWYGdrives -fieldraidarraystatus $ninjafieldraidarraystatus -fieldraidarraydetails $ninjafieldraidarraydetails -resultraidarraydetails $raidarraydetails -resultAllDrives $AllDrives -resultfaileddrives $faileddrives -resultAllvirtual $virtualdrives
    }
    # Write Values to Json
    if($raidarraydetails){
        $raidarraydetails       | ConvertTo-Json | Out-File -FilePath "C:\ProgramData\EasyRaidCheck\Array_Details.json" -Force
    }       
    if($alldrives){
        $alldrives              | ConvertTo-Json | Out-File -FilePath "C:\ProgramData\EasyRaidCheck\Drives_All.json" -Force
    }             
    if($FailedDrives){
        $FailedDrives           | ConvertTo-Json | Out-File -FilePath "C:\ProgramData\EasyRaidCheck\Drives_Failed.json" -Force
    } 
    if($FailedVirtualDrives){
        $FailedVirtualDrives    | ConvertTo-Json | Out-File -FilePath "C:\ProgramData\EasyRaidCheck\Drives_Failed_Virtual.json" -Force
    }
    if($MissingDrives){
        $MissingDrives          | ConvertTo-Json | Out-File -FilePath "C:\ProgramData\EasyRaidCheck\Drives_Missing.json" -Force
    }
    if($virtualdrives){
        $virtualdrives          | ConvertTo-Json | Out-File -FilePath "C:\ProgramData\EasyRaidCheck\Drives_Virtual.json" -Force
    }

    # Output results to screen
    $raidarraydetails | format-table
    if($supported -ne $false) {
        $AllDrives | Select-object Array,DriveNumber,Port,Bay,Status,Reason,Size,Interface,Serial,Model,Temp,'Smart Status' | format-table * -autosize
    } else{
        $AllDrives | format-table * -autosize
        $virtualdrives | format-table * -autosize
    }
    
    if($faileddrives -ne $null){
        Write-Output "Failed Drive Information"
        if($supported -ne $false) {
            $faileddrives | Select-object Array,DriveNumber,Port,Bay,Status,Reason,Size,Interface,Serial,Model,Temp,'Smart Status' | format-table * -autosize
        }else{
            $faileddrives | format-table * -autosize
        }
        exit $ninjaexitcodefailure
    } else {
        exit 0
    }
}