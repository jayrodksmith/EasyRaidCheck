function Start-EasyRaidCheck{
    [CmdletBinding()]
    param (
        # RMM Mode
        [string]$RMM                        = 'NinjaOne',
        # Ninja Custom Fields
        [string]$ninjafieldWYSIWYGdrives    = 'raidtablephysical',          # WYSIWYG field for Ninja
        [string]$ninjafieldraidarraystatus  = 'raidarraystatus',            # Text field for Ninja
        [string]$ninjafieldraidarraydetails = 'raidarraydetails',           # Text field for Ninja
        # Ninja Exit Code
        [int]$ninjaexitcodefailure          = '999',                        # Set this in your condition script result code
        # LSI Details
        [string]$lsiurl                     = "https://downloadmirror.intel.com/743783/Intel_StorCLI_007.1907.0000.0000.zip",
        [string]$lsioutput                  = "C:\temp\storcli.zip",
        [string]$lsiCLILocation             = 'C:\temp\Intel_StorCLI_007.1907.0000.0000\Unified_storcli_all_os\Windows\storcli64.exe',
        # HP Details
        [string]$hpurl                      = "https://downloads.hpe.com/pub/softlib2/software1/sc-windows/p955544928/v183348/cp044527.exe",
        [string]$hpoutput                   = "C:\temp\cp044527.exe", 
        [string]$hpCLILocation              = 'C:\Program Files\Smart Storage Administrator\ssacli\bin\ssacli.exe', # Dont change this, HP tools is a installed program
        [boolean]$Smartinfo                 = $true # This will download CrystalDiskInfo

    )
    # Determine if the system is virtual
    $IsVirtual = @(Get-CimInstance -ClassName Win32_ComputerSystem | Where-Object { $_.Model -eq 'VMware Virtual Platform' -or $_.Model -eq 'Virtual Machine' }).Count -gt 0
    if($IsVirtual){
        return "Not Running because Virtual Machine"
    }
    $supportedcontrollers, $controllers = Get-RaidControllers

    if ($supportedcontrollers.'Controller Type' -match "LSI"){
        # LSI
        $raidarraydetails, $AllDrives, $FailedDrives, $FailedVirtualDrives, $MissingDrives  = Get-RaidControllerLSI -ControllerName ($($supportedcontrollers.'Controller Name') | Select-object -first 1)
    } elseif ($supportedcontrollers.'Controller Type' -match "HP"){
        # HP
        $raidarraydetails, $AllDrives, $faileddrives                                        = Get-RaidControllerhp -ControllerName ($($supportedcontrollers.'Controller Name') | Select-object -first 1)
    } else {
        Write-Output "No Supported Controllers"
        return $controllers
    }
    # Retrieve Smart Details using CrystalDiskInfo if set to true
    if($Smartinfo -eq $true){
        $smartalldrives, $smartFailedDrives                                                 = Get-SMARTInfo
        # Check existing results and merge results if found.
        foreach ($drive in $alldrives) {
            Write-Output "Checking $($drive.Serial)"
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
                if($drive.'Smart Status' -notmatch '\bGood\b'){
                    $drive.'RowColour' = 'danger'
                }
            }
        }
    }

    # Write Values to Ninja
    if($RMM -eq 'Ninjaone'){
        Get-FieldsNinjaRMM -fieldWYSIWYGdrives $ninjafieldWYSIWYGdrives -fieldraidarraystatus $ninjafieldraidarraystatus -fieldraidarraydetails $ninjafieldraidarraydetails
        Write-ResultNinjaRMM -fieldWYSIWYGdrives $ninjafieldWYSIWYGdrives -fieldraidarraystatus $ninjafieldraidarraystatus -fieldraidarraydetails $ninjafieldraidarraydetails -resultraidarraydetails $raidarraydetails -resultAllDrives $AllDrives -resultfaileddrives $faileddrives
    }
    # Output results to screen
    $raidarraydetails | format-table
    $AllDrives | format-table
    if($faileddrives){
        Write-Output "Failed Drive Information"
        $faileddrives | format-table
        exit $ninjaexitcodefailure
    } else {
        exit 0
    }
}