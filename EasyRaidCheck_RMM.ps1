

function Get-RaidControllers{
    [CmdletBinding()]
    param (
    )

    $controllers = Get-CimInstance -ClassName "Win32_SCSIController"
    $found = $false
    
    # Define controller name patterns for different vendors
    $lsiPatterns = "*lsi*", "*megaraid*", "*Intel(R) Integrated RAID Module*", "*Intel(R) RAID Controller*", "*megasas*", "*Avago*", "*ThinkSystem RAID*", "*PERC*"
    $hpPattern = "*Smart Array*"
    $results = @() # Initialize an empty array to store results

    # Find LSI
    foreach ($controller in $controllers) {
        foreach ($pattern in $lsiPatterns) {
            if ($controller.Name -like $pattern) {
                $results += [PSCustomObject]@{
                    "Controller Name" = $controller.Name
                    "Controller Type" = "LSI"
                }
                $found = $true
            }
        }
    }
    # Find HP
    foreach ($controller in $controllers) {
        foreach ($pattern in $hpPattern) {
            if ($controller.Name -like $pattern) {
                $results += [PSCustomObject]@{
                    "Controller Name" = $controller.Name
                    "Controller Type" = "HP"
                }
                $found = $true
            }
        }
    }
    return $results, $controllers
}

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
        [string]$hpCLILocation              = 'C:\Program Files\Smart Storage Administrator\ssacli\bin\ssacli.exe' # Dont change this, HP tools is a installed program

    )

$supportedcontrollers, $controllers = Get-RaidControllers

if ($supportedcontrollers.'Controller Type' -match "LSI"){
    # LSI
    $raidarraydetails, $AllDrives, $FailedDrives, $FailedVirtualDrives, $MissingDrives          = Get-RaidControllerLSI -ControllerName ($($supportedcontrollers.'Controller Name') | Select-object -first 1)
} elseif ($supportedcontrollers.'Controller Type' -match "HP"){
    # HP
    $raidarraydetails, $AllDrives, $faileddrives                                                = Get-RaidControllerhp -ControllerName ($($supportedcontrollers.'Controller Name') | Select-object -first 1)
} else {
    Write-Output "No Supported Controllers"
    return $controllers
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

function Get-RaidControllerHP{
    [CmdletBinding()]
    param (
        [string]$hpCLILocation = 'C:\Program Files\Smart Storage Administrator\ssacli\bin\ssacli.exe',
        [string]$controllerName = "Unknown"
    )
    
    Get-RaidControllerHPPreReq
    $hpraidstatus = & $hpCLILocation ctrl all show status | Out-String
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
            $hpraidstatusslot_array += & $hpCLILocation ctrl slot=$slotNumber array all show status | Out-String
            $hpraidstatusslot_pd += & $hpCLILocation ctrl slot=$slotNumber pd all show | Out-String
            $hpraidstatusslot_ld += & $hpCLILocation ctrl slot=$slotNumber ld all show | Out-String
    }
    $PhysicalStatus = ""

    # Log all drives
    $PhysicalStatus = $hpraidstatusslot_pd
    $AllDrives = New-Object System.Collections.Generic.List[Object]
    $PhysicalStatus_drivenumbers = ($PhysicalStatus -split "`n" | Select-String -Pattern "physicaldrive" | ForEach-Object { [regex]::Match($_, '(\d+[A-Z]:\d+:\d+)').Value })
    foreach ($PhysicalStatus_drivenumber in $PhysicalStatus_drivenumbers) {
        $hpraidstatusslot_pd_details = & $hpCLILocation ctrl slot=$slotNumber pd "$PhysicalStatus_drivenumber" show detail | Out-String
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
            Array = $Array
            DriveNumber = $PhysicalStatus_drivenumber
            Port = $port
            Bay = $bay
            Status = $status
            Reason = $reason
            Size = $size
            Interface = $interface
            Serial = $serialNumber
            Model = $model
            'Temp' = $Currenttemperature
            'Max Temp' = $Maximumtemperature
            RowColour = $RowColour
        })
    }
    if ($hpraidstatus -like "*Failure*" -or $hpraidstatus -like "*Failed*" -or $hpraidstatus -like "*Error*" -or $hpraidstatusslot_array -like "*Failed*" -or $hpraidstatusslot_pd -like "*Failed*") {
        $RAIDStatus = "Not Healthy"
    }
    $FailedDrives = $AllDrives | Where-Object -Property Status -eq 'Failed'
    if($FailedDrives) {
        $RAIDphysicalstatus = "Not Healthy"
    }
    
    ## Get Details of failed drive  
    if (!$RAIDStatus) {
        $RAIDStatus = "Healthy"
    }
    if ($null -eq $PhysicalStatus) {
        $PhysicalStatus = "Healthy"
    }
    
    $raidarraydetails = New-Object System.Collections.Generic.List[Object]
    $raidarraydetails.Add([PSCustomObject]@{
        Controller              = $controllerName
        VirtualStatus           = $RAIDStatus
        PhysicalStatus          = $RAIDphysicalstatus
    })

    return $raidarraydetails, $AllDrives, $faileddrives
}

function Get-RaidControllerHPPreReq {
    [CmdletBinding()]
    param (
        $hpurl = "https://downloads.hpe.com/pub/softlib2/software1/sc-windows/p955544928/v183348/cp044527.exe", # URL for HP Tools
        $hpoutput = "C:\temp\cp044527.exe",
        $hpCLILocation = 'C:\Program Files\Smart Storage Administrator\ssacli\bin\ssacli.exe'
    )
    if (-not(Test-Path -Path $hpCLILocation -PathType Leaf)) {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        try {
            Write-Verbose "HP Tools downloading and installing"
            Invoke-WebRequest -Uri $hpurl -OutFile $hpoutput
            Start-Process -FilePath 'C:\temp\cp044527.exe' -ArgumentList "/s"
        }catch{
            Write-Error "An error occurred: $_"
        }
    }else{
        Write-Verbose "HP Tools already installed"
    }
}

## Intial Code Here

## Intial Code Here

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

function Get-RaidControllerLSIPreReq {
    [CmdletBinding()]
    param (
        $lsiurl = "https://downloadmirror.intel.com/743783/Intel_StorCLI_007.1907.0000.0000.zip", # URL for StorCLI
        $lsioutput = "C:\temp\storcli.zip",
        $lsiCLILocation = 'C:\temp\Intel_StorCLI_007.1907.0000.0000\Unified_storcli_all_os\Windows\storcli64.exe'
    )
    if (-not(Test-Path -Path $lsiCLILocation -PathType Leaf)) {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        try {
            Write-Verbose "LSI Tools downloading and extracting"
            Invoke-WebRequest -Uri $lsiurl -OutFile $lsioutput
            Expand-File -File $lsioutput -Destination "C:\temp"
        }catch{
            Write-Error "An error occurred: $_"
        }
    }else{
        Write-Verbose "LSI Tools already exists"
    }
}

function Expand-File{
    [CmdletBinding()]
    param (
        $file,
        $destination
    )
    Function Test-CommandExists {
        Param (
            $command
        )
        $oldPreference = $ErrorActionPreference
        $ErrorActionPreference = 'stop'
        try {
            if(Get-Command $command){
                return $true
            }
        } Catch {
            Write-Verbose "$command does not exist"
            return $false
        } Finally {
            $ErrorActionPreference=$oldPreference
        }
    }
    if (Test-CommandExists 'Expand-Archive' -eq $True ){
        $commandexist = $True
        } else {
        $commandexist = $False
        }
    if($commandexist -eq $True) {
        Expand-Archive -Path $file -DestinationPath $destination
    } else {
        $shell = new-object -com shell.application
        $zip = $shell.NameSpace($file)
        foreach($item in $zip.items()){
            $shell.Namespace($destination).copyhere($item, 0x14)
        }
    }
}

function Get-DownloadUrls {
    [CmdletBinding()]
    param (
    )
}

function ConvertTo-ObjectToHtmlTable {
    param (
        [Parameter(Mandatory=$true)]
        [System.Collections.Generic.List[Object]]$Objects
    )
    #
    #   "unknown"   is grey
    #   "other"     is blue
    #   "danger"    is red
    #   "warning"   is amber
    #   "success"   is green

    $sb = New-Object System.Text.StringBuilder

    # Start the HTML table
    [void]$sb.Append('<table><thead><tr>')

    # Add column headers based on the properties of the first object, excluding "RowColour"
    $Objects[0].PSObject.Properties.Name |
        Where-Object { $_ -ne 'RowColour' } |
        ForEach-Object { [void]$sb.Append("<th>$_</th>") }

    [void]$sb.Append('</tr></thead><tbody>')

    foreach ($obj in $Objects) {
        # Use the RowColour property from the object to set the class for the row
        $rowClass = if ($obj.RowColour) { $obj.RowColour } else { "" }

        [void]$sb.Append("<tr class=`"$rowClass`">")
        # Generate table cells, excluding "RowColour"
        foreach ($propName in $obj.PSObject.Properties.Name | Where-Object { $_ -ne 'RowColour' }) {
            [void]$sb.Append("<td>$($obj.$propName)</td>")
        }
        [void]$sb.Append('</tr>')
    }

    [void]$sb.Append('</tbody></table>')

    return $sb.ToString()
}

function Get-FieldsNinjaRMM {
    <#
        .SYNOPSIS
        Function to get details to NinjaRMM
    
        .DESCRIPTION
        This function will get details to NinjaRMM
    
        .EXAMPLE
        Get-WarrantyNinjaRMM

    #>
        [CmdletBinding(SupportsShouldProcess)]
        param (
            [string]$fieldWYSIWYGdrives    = '',
            [string]$fieldraidarraystatus  = '',
            [string]$fieldraidarraydetails = ''
        )
        # Import Ninja Powershell Module
        Write-Verbose "Importing Ninja Powershell module"
        Import-Module NJCliPSh -ErrorAction SilentlyContinue -WarningAction SilentlyContinue -verbose:$false | Out-Null
        # Test if fields exist
        $testninjafieldWYSIWYGdrives = Ninja-Property-Get $fieldWYSIWYGdrives 2>&1
        if ($testninjafieldWYSIWYGdrives -match "Unable to find the specified field" ){
            Write-Host "Unable to access $fieldWYSIWYGdrives field in ninja"
            Write-Host "Check permissions of field and that it exists"
            Set-Variable testninjafieldWYSIWYGdrives -Value $false -Scope Global -option ReadOnly -Force
        }
        $testninjafieldraidarraystatus  = Ninja-Property-Get $fieldraidarraystatus  2>&1
        if ($testninjafieldraidarraystatus  -match "Unable to find the specified field" ){
            Write-Host "Unable to access $fieldraidarraystatus field in ninja"
            Write-Host "Check permissions of field and that it exists"
            Set-Variable testninjafieldraidarraystatus -Value $false -Scope Global -option ReadOnly -Force
        }
        $testninjafieldraidarraydetails  = Ninja-Property-Get $fieldraidarraydetails  2>&1
        if ($testninjafieldraidarraydetails  -match "Unable to find the specified field" ){
            Write-Host "Unable to access $fieldraidarraydetails field in ninja"
            Write-Host "Check permissions of field and that it exists"
            Set-Variable testninjafieldraidarraydetails -Value $false -Scope Global -option ReadOnly -Force
        }
    }

function Write-ResultNinjaRMM {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [string]$fieldWYSIWYGdrives         = '',
        [string]$fieldraidarraystatus       = '',
        [string]$fieldraidarraydetails      = '',
        [string]$resultraidarraydetails     = '',
        [System.Collections.Generic.List[Object]]$resultAllDrives,
        [string]$resultfaileddrives         = ''
    )
    if (-not (Get-Command -Name "Ninja-Property-Set" -ErrorAction SilentlyContinue)) {
        $errorMessage = "Error: NinjaRMM module not found, not writing to NinjaRMM."
        return $errorMessage
    }
    # Set standard Custom fields
    if (($resultraidarraydetails."VirtualStatus" -eq "Healthy") -and ($resultraidarraydetails."PhysicalStatus" -eq "Healthy")) {
        if($testninjafieldraidarraystatus -ne $false){
            Write-Verbose "Will try write raidarraystatus value"
            Ninja-Property-Set $fieldraidarraystatus "Healthy"
        }
        if($testninjafieldraidarraydetails -ne $false){
            Write-Verbose "Will try write raidarraydetails value"
            $resultraidarraydetails | Ninja-Property-Set-Piped -Name $fieldraidarraydetails
        }
    } else {
        if($testninjafieldraidarraystatus -ne $false){
            Write-Verbose "Will try write raidarraystatus value"
            Ninja-Property-Set $fieldraidarraystatus "Not Healthy"
        }
        if($testninjafieldraidarraydetails -ne $false){
            Write-Verbose "Will try write raidarraydetails value"
            $resultraidarraydetails | Ninja-Property-Set-Piped -Name $fieldraidarraydetails
        }
    }
    # Set WYSIWYG Custom fields
    if($resultAllDrives){
        if($testninjafieldWYSIWYGdrives -ne $false){
            Write-Verbose "Will try write WYSIWYGdrives value"
            $htmlTable = ConvertTo-ObjectToHtmlTable -Objects $resultAllDrives
            $htmlTable | Ninja-Property-Set-Piped -Name $fieldWYSIWYGdrives
        }
    }
}

## Intial Code Here

Start-EasyRaidCheck
