

function Get-RaidControllers{
    [CmdletBinding()]
    param (
    )

    $controllers = Get-CimInstance -ClassName "Win32_SCSIController"
    $found = $false
    
    # Define controller name patterns for different vendors
    $lsiPatterns = "*lsi*", "*megaraid*", "*Intel(R) Integrated RAID Module*", "*Intel(R) RAID Controller*", "*Intel Embedded Server RAID Technology II*","*ServeRAID*", "*megasas*", "*Avago*","*Lenovo ThinkServer RAID*", "*ThinkSystem RAID*", "*Asustek pike 2208*", "*ASUSTEK PIKE II*","*Intel(R) Integrated RAID RS3*", "*SAS3008*","*SAS3108*","*SAS2208*","*Gigabyte MR-3108*","*MSI S101B IMR*","*SAS3004*","*ASRR_M3108*"
    $percPattern = "*PERC*"
    $hpPattern = "*Smart Array*", "*Adaptec SmartHBA-SA*", "*Microchip Adaptec HBA 1000*"
    $vrocPattern = "*VROC*"
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
    # Find PERC
    foreach ($controller in $controllers) {
        foreach ($pattern in $percPattern) {
            if ($controller.Name -like $pattern) {
                $results += [PSCustomObject]@{
                    "Controller Name" = $controller.Name
                    "Controller Type" = "PERC"
                }
                $found = $true
            }
        }
    }
    # Find VROC
    foreach ($controller in $controllers) {
        foreach ($pattern in $vrocPattern) {
            if ($controller.DriverName -like $pattern) {
                $results += [PSCustomObject]@{
                    "Controller Name" = $controller.Name
                    "Controller Type" = "VROC"
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
        [string]$perccli64                  = 'C:\ProgramData\EasyRaidCheck\Dell\perccli64.exe',    # Will download from my github if missing
        # VROC Details
        [string]$vroccli                    = 'C:\ProgramData\EasyRaidCheck\VROC\IntelVROCCli.exe',   # Will download from my github if missing
        # CrystalDiskInfo Details
        [boolean]$Smartinfo                 = $true ,                                               # This will download CrystalDiskInfo if missing
        $DiskInfo64                         = "C:\ProgramData\EasyRaidCheck\Crystaldiskinfo\DiskInfo64.exe"

    )
    Write-Output "EasyRaidCheck Version 1.5.0"
    # Determine if the system is virtual
    $IsVirtual = @(Get-CimInstance -ClassName Win32_ComputerSystem | Where-Object { $_.Model -eq 'VMware Virtual Platform' -or $_.Model -eq 'Virtual Machine' }).Count -gt 0
    if($IsVirtual){
        return "Not Running because Virtual Machine"
    }
    $supportedcontrollers, $controllers = Get-RaidControllers

    if ($supportedcontrollers.'Controller Type' -match "LSI"){
        # LSI
        $raidarraydetails, $AllDrives, $virtualdrives, $FailedDrives, $FailedVirtualDrives, $MissingDrives  = Get-RaidControllerLSI -StorCLILocation $storecli64
    } elseif ($supportedcontrollers.'Controller Type' -match "HP"){
        # HP
        $raidarraydetails, $AllDrives, $virtualdrives, $faileddrives                                        = Get-RaidControllerHP -hpCLIlocation $ssacli -hpADUlocation $ssaducli -ControllerName ($($supportedcontrollers.'Controller Name') | Select-object -first 1)
    } elseif ($supportedcontrollers.'Controller Type' -match "PERC"){
        # PERC
        $raidarraydetails, $AllDrives, $virtualdrives, $faileddrives, $FailedVirtualDrives, $MissingDrives  = Get-RaidControllerPERC -percCLILocation $perccli64
    } elseif ($supportedcontrollers.'Controller Type' -match "VROC"){
        # VROC
        $raidarraydetails, $AllDrives, $virtualdrives, $faileddrives, $FailedVirtualDrives, $MissingDrives  = Get-RaidControllerVROC -vrocCLILocation $vroccli
        $vroconly = $true
    } else {
        Write-Output "No Supported Controllers"
        $supported = $false
        $raidarraydetails = New-Object System.Collections.Generic.List[Object]
        $raidarraydetails.Add([PSCustomObject]@{
            Supported          = $false
        })
    }
    if (($supportedcontrollers.'Controller Type' -match "VROC") -and ($supported -ne $false)-and ($vroconly -ne $true)){
        # VROC
        $raidarraydetails2, $AllDrives2, $virtualdrives2, $faileddrives2, $FailedVirtualDrives2, $MissingDrives2  = Get-RaidControllerVROC -vrocCLILocation $vroccli
        $raidarraydetails.AddRange($raidarraydetails2)
        $AllDrives.AddRange($AllDrives2)
        $virtualdrives.AddRange($virtualdrives2)
        if ($faileddrives2){
            $faileddrives.AddRange($faileddrives2)
        }
        if ($FailedVirtualDrives2){
            $FailedVirtualDrives.AddRange($FailedVirtualDrives2)
        }
        if ($MissingDrives2){
            $MissingDrives.AddRange($MissingDrives2)
        }
    }

    # Retrieve Smart Details using CrystalDiskInfo if set to true
    if ($Smartinfo -eq $true) {
        $smartalldrives, $smartFailedDrives = Get-SMARTInfo -CDIPath $DiskInfo64
    
        # Check existing results and merge results if found.
        if ($supported -ne $false) {
            $updatedDrives = @()
            foreach ($drive in $alldrives) {
                $serial = $($drive.Serial)
                $smartDrive = $smartalldrives | Where-Object { $_.'Serial Number' -eq $serial }
                if ($smartDrive) {
                    # Merge existing fields from $smartalldrives into $alldrives and set danger flag if required
                    $drive.'Smart Status' = $($smartDrive.'Health Status')
                    $drive.'Power On Hours' = $($smartDrive.'Power On Hours')
                    $drive.'DriveLetter' = $($smartDrive.'Drive Letter')
                    if ($null -eq $drive.'Temp') {
                        $drive.'Temp' = $($smartDrive.'Temperature')
                    }
                    if ($null -eq $drive.'Size') {
                        $drive.'Size' = $($smartDrive.'Disk Size')
                    }
                    if ($null -eq $drive.'Model') {
                        $drive.'Model' = $($smartDrive.'Model')
                    }
                    $percentage = [regex]::Match($drive.'Smart Status', '\((\d+)\s*%\)').Groups[1].Value
                    if ($drive.'Smart Status' -notmatch '\bGood\b' -and $null -ne $drive.'Smart Status' -and $drive.'Smart Status' -notmatch '\bUnknown\b') {
                        $drive.'RowColour' = 'danger'
                    }
                    $updatedDrives += $drive
                } else {
                    # Add the original drive to the updated list
                    $updatedDrives += $drive
                }
            }
            
            # Add non-matching smart drives to $updatedDrives
            $smartDrivenotmatched = $smartalldrives | Where-Object { $_.'Serial Number' -notin $alldrives.Serial }
            foreach ($smartDrive in $smartDrivenotmatched) {
                $newDrive = [PSCustomObject]@{
                    'Controller'        = $null
                    'Array'             = $null
                    'DriveNumber'       = $null
                    'Port'              = $null
                    'Bay'               = $null
                    'Status'            = $null
                    'Reason'            = $null
                    'Size'              = $smartDrive.'Disk Size'
                    'Interface'         = $smartDrive.'Interface'
                    'Serial'            = $smartDrive.'Serial Number'
                    'Model'             = $smartDrive.'Model'
                    'Temp'              = $smartDrive.'Temperature'
                    'Max Temp'          = $null
                    'Smart Status'      = $smartDrive.'Health Status'
                    'Power On Hours'    = $smartDrive.'Power On Hours'
                    'DriveLetter'       = $smartDrive.'Drive Letter'
                    'RowColour'         = $smartDrive.'RowColour'
                }
                $updatedDrives += $newDrive
            }
            
            $alldrives = $updatedDrives
        } else {
            $alldrives = $smartalldrives
            $faileddrives = $smartFailedDrives
        }
    }
    # Write Values to Ninja
    if($RMM -eq 'Ninjaone'){
        Get-FieldsNinjaRMM -fieldWYSIWYGdrives $ninjafieldWYSIWYGdrives -fieldWYSIWYGvirtual $ninjafieldWYSIWYGvirtual -fieldWYSIWYGstatus $ninjafieldWYSIWYGstatus -fieldraidarraystatus $ninjafieldraidarraystatus -fieldraidarraydetails $ninjafieldraidarraydetails
        Write-ResultNinjaRMM -fieldWYSIWYGdrives $ninjafieldWYSIWYGdrives -fieldWYSIWYGvirtual $ninjafieldWYSIWYGvirtual -fieldWYSIWYGstatus $ninjafieldWYSIWYGstatus -fieldraidarraystatus $ninjafieldraidarraystatus -fieldraidarraydetails $ninjafieldraidarraydetails -resultraidarraydetails $raidarraydetails -resultAllDrives $AllDrives -resultfaileddrives $faileddrives -resultAllvirtual $virtualdrives
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

    # Properties to exclude from output
    $excludeProperties = @(
        "RowColour"
        "Rebuild Remaining"
        "Driver"
        "Firmware"
        )

    # Output results to screen use Format List if Format Table execeeds Ninja Limits
    
    if ($raidarraydetails){
        $properties = $raidarraydetails[0].PSObject.Properties.Name | Where-Object { $_ -notin $excludeProperties }
        $raidarraydetails = $raidarraydetails | Select-Object $properties
        if((Test-FormattedTableWidth -Object $raidarraydetails) -eq $false){
            $raidarraydetails | Format-Table -AutoSize
        } else{
            $raidarraydetails | Format-List
        }
    }

    if($supported -ne $false) {
        $Alldrives = $AllDrives | Select-object Array,Port,Size,Interface,Serial,Model,Temp,'Smart Status'
        if((Test-FormattedTableWidth -Object $Alldrives) -eq $false){
            $Alldrives | Format-Table
        } else{
            $Alldrives | Format-List
        }
        if((Test-FormattedTableWidth -Object $virtualdrives) -eq $false){
            $virtualdrives | Format-Table
        }else{
            $virtualdrives | Format-List
        }
    } else{
        if((Test-FormattedTableWidth -Object $Alldrives) -eq $false){
            $AllDrives | Format-Table
        } else {
            $AllDrives | Format-List
        }
    }
    
    if($null -ne $faileddrives){
        Write-Output "Failed Drive Information"
        if($supported -ne $false) {
            $faileddrives = $faileddrives | Select-object Array,Port,Size,Interface,Serial,Model,Temp,'Smart Status'
            if((Test-FormattedTableWidth -Object $faileddrives) -eq $false){
                $faileddrives | Format-Table
            } else{
                $faileddrives | Format-List
            }
        }else{
            if((Test-FormattedTableWidth -Object $faileddrives) -eq $false){
                $faileddrives | Format-Table
            } else{
                $faileddrives | Format-List
            }
        }
        exit $ninjaexitcodefailure
    } else {
        exit 0
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
        Expand-Archive -Path $file -DestinationPath $destination -Force
    } else {
        $shell = new-object -com shell.application
        $zip = $shell.NameSpace($file)
        foreach($item in $zip.items()){
            $shell.Namespace($destination).copyhere($item, 0x14)
        }
    }
}

function Test-FormattedTableWidth {
    # Example
    # Test-FormattedTableWidth -Object $object -Width 114
    # Checks if table is larger than 114 characters, which Ninja's Limit is on the console view
    param (
        [Parameter(Mandatory = $true)]
        [psobject]$Object,
        
        [int]$Width = 114
    )

    # Format the object as a table and output it as a string with the specified width
    $formattedOutput = $Object | Format-Table | Out-String -Width $Width

    # Measure the width of the formatted output
    $maxWidth = ($formattedOutput -split "`n" | ForEach-Object { $_.Length }) | Measure-Object -Maximum
    return $maxWidth.Maximum -gt $Width
}

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
    $smartfaileddrives = @()
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

function Get-SMARTPreReq {
    [CmdletBinding()]
    param (
        $crystalurl = "https://ixpeering.dl.sourceforge.net/project/crystaldiskinfo/9.3.0/CrystalDiskInfo9_3_0.zip?viasf=1",
        $crystaloutput = "$($env:windir)\temp\CrystalDiskInfo.zip",
        $crystalLocation = "",
        $crystalextract = "C:\ProgramData\EasyRaidCheck\Crystaldiskinfo"
    )
    # Check if the folder exists
    if (-not (Test-Path -Path $crystalextract)) {
        # If it doesn't exist, create it
        $newfolder = New-Item -Path $crystalextract -ItemType Directory -erroraction SilentlyContinue | Out-null
    } 
    if (-not(Test-Path -Path $crystalLocation -PathType Leaf)) {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        try {
            Write-Verbose "Extracting CrystalDiskInfo"
            Invoke-WebRequest -Uri $crystalurl -OutFile $crystaloutput
            Expand-File -File $crystaloutput -Destination $crystalextract
        }catch{
            Write-Error "An error occurred: $_"
            exit 888
        }
    }else{
        Write-Verbose "CrystalDiskInfo already exists"
    }
}

function Get-RaidControllerLSI {
    [CmdletBinding()]
    param (
        [string]$StorCLILocation = 'C:\ProgramData\EasyRaidCheck\LSI\storcli64.exe'
    )

    Get-RaidControllerLSIPreReq -lsiCLILocation $StorCLILocation

    $alldrives              = New-Object System.Collections.Generic.List[Object]
    $missingdrives          = New-Object System.Collections.Generic.List[Object]
    $failedvirtualdrives    = New-Object System.Collections.Generic.List[Object]
    $faileddrives           = New-Object System.Collections.Generic.List[Object]
    $raidarraydetails       = New-Object System.Collections.Generic.List[Object]
    $virtualdrivesgroup     = New-Object System.Collections.Generic.List[Object]
    $virtualdrives          = New-Object System.Collections.Generic.List[Object]

    try {
        $ExecuteStorCliCommandbasicinfo     = & $StorCLILocation "show all"
        $controllerCountMatch               = $ExecuteStorCliCommandbasicinfo | Select-String -Pattern "Number of Controllers\s*=\s*(\d+)"
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
            
            $StorCliCommandvirtualdrive             = "$controller /vall show j"
            $StorCliCommandvirtualdrivegroup        = "$controller /dall show j"
            $StorCliCommandphysical                 = "$controller /eall /sall show j"
            $StorCliCommandphysicalall              = "$controller /eall /sall show all"
            $StorCliCommandbasicinfo2               = "$controller show"
            $StorCliCommandrebuildprogress          = "$controller /eall /sall show rebuild"

            $ExecuteStorCLIvirtualdrive             = & $StorCLILocation $StorCliCommandvirtualdrive | out-string
            $ArrayStorCLIvirtualdrive               = ConvertFrom-Json $ExecuteStorCLIvirtualdrive
            $ExecuteStorCLIvirtualdrivegroup        = & $StorCLILocation $StorCliCommandvirtualdrivegroup | out-string
            $ArrayStorCLIvirtualdrivegroup          = ConvertFrom-Json $ExecuteStorCLIvirtualdrivegroup
            $ExecuteStorCliCommandbasicinfo2        = & $StorCLILocation $StorCliCommandbasicinfo2
            $ExecuteStorCliCommandrebuildprogress   = & $StorCLILocation $StorCliCommandrebuildprogress

            $LSIcontrollermodel                     = $ExecuteStorCliCommandbasicinfo2 | Select-String -Pattern "Product Name\s*=\s*(.*)" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() }
            $LSIcontrollerserial                    = $ExecuteStorCliCommandbasicinfo2 | Select-String -Pattern "Serial Number\s*=\s*(.*)" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() }
            $LSIcontrollerfirmware                  = $ExecuteStorCliCommandbasicinfo2 | Select-String -Pattern "FW Version\s*=\s*(.*)" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() }
            $LSIcontrollerdriver                    = $ExecuteStorCliCommandbasicinfo2 | Select-String -Pattern "Driver Version\s*=\s*(.*)" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() }

            # Get Virtual Drive Status + Physical
            foreach ($VirtualDrivegroup in $ArrayStorCLIvirtualdrivegroup.Controllers.'response data'.'response data'.'TOPOLOGY') {
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
            foreach ($VirtualDrive in $ArrayStorCLIvirtualdrive.Controllers.'response data'.'Virtual Drives') {
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

            $ExecuteStorCLIphysical     = & $StorCLILocation $StorCliCommandphysical | out-string
            $ArrayStorCLIphysical       = ConvertFrom-Json $ExecuteStorCLIphysical
            $ExecuteStorCLIphysicalall  = & $StorCLILocation $StorCliCommandphysicalall | out-string
            $driveEntries               = $ExecuteStorCLIphysicalall -split [System.Environment]::NewLine
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

            foreach ($physicaldrive in $ArrayStorCLIphysical.Controllers.'Response data'.'Drive Information') {
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

            $lines = $ExecuteStorCliCommandrebuildprogress -split "\r?\n"
            $lines | Where-Object { $_ -notmatch "Not in progress" } | ForEach-Object {
                if ($_ -match "(\d+)\s+In progress\s+(.+)$") {
                    $rebuildpercentage = $matches[1] + " %"
                    $estimatedTimeLeft = $matches[2]
                }
            }

            $raidarraydetails.Add([PSCustomObject]@{
                Controller          = $controllertrimmed
                Model               = $LSIcontrollermodel
                Serial              = $LSIcontrollerserial
                Firmware            = $LSIcontrollerfirmware
                Driver              = $LSIcontrollerdriver
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
        $ScriptError = "StorCli Command has Failed: $($_.Exception.Message)"
        exit
    }

    return $raidarraydetails, $alldrives, $virtualdrives, $FailedDrives, $FailedVirtualDrives, $MissingDrives
}


function Get-RaidControllerLSIPreReq {
    [CmdletBinding()]
    param (
        $lsiurl = "https://downloadmirror.intel.com/743783/Intel_StorCLI_007.1907.0000.0000.zip", # URL for StorCLI
        $lsioutput = "$($env:windir)\temp\storcli.zip",
        $lsiCLILocation = "",
        $lsiCLILocationtemp = 'C:\ProgramData\EasyRaidCheck\LSI\Intel_StorCLI_007.1907.0000.0000\Unified_storcli_all_os\Windows\storcli64.exe',
        $lsifolder = "C:\ProgramData\EasyRaidCheck\LSI"
    )
    # Check if the folder exists
    if (-not (Test-Path -Path $lsifolder)) {
        # If it doesn't exist, create it
        $newfolder = New-Item -Path $lsifolder -ItemType Directory -erroraction SilentlyContinue | Out-null
    } 
    if (-not(Test-Path -Path $lsiCLILocation -PathType Leaf)) {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        try {
            Write-Verbose "LSI Tools downloading and extracting"
            Invoke-WebRequest -Uri $lsiurl -OutFile $lsioutput
            Expand-File -File $lsioutput -Destination $lsifolder
            Move-Item -Path $lsiCLILocationtemp -Destination $lsifolder -Force
            Remove-Item -Path "C:\ProgramData\EasyRaidCheck\LSI\Intel_StorCLI_007.1907.0000.0000" -Recurse
        }catch{
            Write-Error "An error occurred: $_"
            exit 888
        }
    }else{
        Write-Verbose "LSI Tools already exists"
    }
}

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


function Get-RaidControllerVROCPreReq {
    [CmdletBinding()]
    param (
        $vrocurl = "https://raw.githubusercontent.com/jayrodksmith/EasyRaidCheck/main/Public/VROC/IntelVROCCli.exe", # URL for IntelVROCCli
        $vrocLocation = "",
        $vrocfolder = "C:\ProgramData\EasyRaidCheck\VROC"
    )
    # Check if the folder exists
    if (-not (Test-Path -Path $vrocfolder)) {
        # If it doesn't exist, create it
        $newfolder = New-Item -Path $vrocfolder -ItemType Directory -erroraction SilentlyContinue | Out-null
    } 
    if (-not(Test-Path -Path $vrocLocation -PathType Leaf)) {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        try {
            Write-Verbose "VROC Tools downloading and extracting"
            Invoke-WebRequest -Uri $vrocurl -OutFile $vrocLocation
        }catch{
            Write-Error "An error occurred: $_"
            exit 888
        }
    }else{
        Write-Verbose "VROC Tools already exists"
    }
}

function Get-RaidControllerPERC {
    [CmdletBinding()]
    param (
        [string]$percCLILocation = 'C:\ProgramData\EasyRaidCheck\Dell\perccli64.exe'
    )

    Get-RaidControllerPERCPreReq -percLocation $percCLILocation

    $alldrives              = New-Object System.Collections.Generic.List[Object]
    $missingdrives          = New-Object System.Collections.Generic.List[Object]
    $failedvirtualdrives    = New-Object System.Collections.Generic.List[Object]
    $faileddrives           = New-Object System.Collections.Generic.List[Object]
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


function Get-RaidControllerPERCPreReq {
    [CmdletBinding()]
    param (
        $percurl = "https://raw.githubusercontent.com/jayrodksmith/EasyRaidCheck/main/Public/PERC/perccli64.exe", # URL for StorCLI
        $percLocation = "",
        $percfolder = "C:\ProgramData\EasyRaidCheck\Dell"
    )
    # Check if the folder exists
    if (-not (Test-Path -Path $percfolder)) {
        # If it doesn't exist, create it
        $newfolder = New-Item -Path $percfolder -ItemType Directory -erroraction SilentlyContinue | Out-null
    } 
    if (-not(Test-Path -Path $percLocation -PathType Leaf)) {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        try {
            Write-Verbose "PERC Tools downloading and extracting"
            Invoke-WebRequest -Uri $percurl -OutFile $percLocation
        }catch{
            Write-Error "An error occurred: $_"
            exit 888
        }
    }else{
        Write-Verbose "PERC Tools already exists"
    }
}

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
            'DriveLetter'               = $null
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

    # Define regular expressions to extract information
    $arrayRegex = 'Array\s+(\w+)'
    $logicalDriveRegex = 'logicaldrive\s+(\d+)\s*\(([^,]+),\s*([^,]+),\s*([^,]+)(?:,\s*([^)]+))?\)'

    # Define a function to extract information from a logical drive string
    function Get-LogicalDriveInfo {
        param([string]$array, [string]$logicalDriveString)
        
        if ($logicalDriveString -match $logicalDriveRegex) {
            [PSCustomObject]@{
                Array               = $array.Trim()
                Name                = "logicaldrive $($matches[1])"
                Size                = $matches[2].Trim()
                RaidType            = $matches[3].Trim()
                Status              = $matches[4].Trim()
                Progress            = if ($matches[5]) { $matches[5].Trim() } else { $null }
                RowColour           = if($matches[4].Trim() -ne "OK" ) {'warning'} else {'success'}
            }
        }
    }

    # Create a list to store logical drive information
    $virtualdrives = New-Object System.Collections.Generic.List[Object]

    # Extract logical drive information
    $currentArray = $null
    foreach ($line in $hpraidstatusslot_ld -split "`n") {
        if ($line -match $arrayRegex) {
            $currentArray = $matches[1]
        }
        elseif ($line -match 'logicaldrive') {
            $virtualdrives.Add((Get-LogicalDriveInfo -array $currentArray -logicalDriveString $line))
        }
    }

    # Extract Percentage if rebuilding
    $rebuildpercentage = [regex]::Match($hpraidstatusslot_ld, '\d+\.\d+%').Value

    $raidarraydetails = New-Object System.Collections.Generic.List[Object]
    $raidarraydetails.Add([PSCustomObject]@{
        Controller              = $controllerName
        'Rebuild Status'        = if($rebuildpercentage -ne ""){$rebuildpercentage}else{"Not Rebuilding"}
        VirtualStatus           = $RAIDStatus
        PhysicalStatus          = $RAIDphysicalstatus
        RowColour               = if (($RAIDStatus -eq 'Not Healthy') -or ($RAIDphysicalstatus -eq 'Not Healthy')) {"danger"}elseif ($rebuildpercentage -ne "") {'warning'}else{"success"}
    })

    return $raidarraydetails, $AllDrives, $virtualdrives, $faileddrives
}

function Get-RaidControllerHPPreReq {
    [CmdletBinding()]
    param (
        $hpurl = "https://downloads.hpe.com/pub/softlib2/software1/sc-windows/p632700740/v238698/cp058578.exe", # URL for HP CLI
        $hpurl2 = "https://downloads.hpe.com/pub/softlib2/software1/sc-windows/p1394061884/v238699/cp058579.exe",# URL for HP ADU
        $hpoutput = "$($env:windir)\temp\cp058578.exe",
        $hpoutput2 = "$($env:windir)\temp\cp058579.exe",
        $hpCLILocation = 'C:\Program Files\Smart Storage Administrator\ssacli\bin\ssacli.exe',
        $hpCLILocation2 = 'C:\Program Files\Smart Storage Administrator\ssaducli\bin\ssaducli.exe',
        $hpLocationcli = "",
        $hpLocationadu = "",
        $hpfolder = "C:\ProgramData\EasyRaidCheck\HP"
    )
    if (-not (Test-Path -Path $hpfolder)) {
        # If it doesn't exist, create it
        $newfolder = New-Item -Path $hpfolder -ItemType Directory -erroraction SilentlyContinue | Out-null
    } 
    if (-not(Test-Path -Path $hpLocationcli -PathType Leaf)) {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        try {
            Write-Verbose "HP CLI downloading and installing"
            Invoke-WebRequest -Uri $hpurl -OutFile $hpoutput
            Start-Process -FilePath $hpoutput -ArgumentList "/s" -wait
            Copy-Item -Path $hpCLILocation -Destination $hpfolder -Force
        }catch{
            Write-Error "An error occurred: $_"
            exit 888
        }
    }else{
        Write-Verbose "HP CLI already installed"
    }
    if (-not(Test-Path -Path $hpLocationadu -PathType Leaf)) {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        try {
            Write-Verbose "HP ADU downloading and installing"
            Invoke-WebRequest -Uri $hpurl2 -OutFile $hpoutput2
            Start-Process -FilePath $hpoutput2 -ArgumentList "/s" -wait
            Copy-Item -Path $hpCLILocation2 -Destination $hpfolder -Force
        }catch{
            Write-Error "An error occurred: $_"
            exit 888
        }
    }else{
        Write-Verbose "HP ADU already installed"
    }
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
            [string]$fieldWYSIWYGvirtual   = '',
            [string]$fieldWYSIWYGstatus    = '',
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
            Write-Host "Check permissions of WYSIWYG field and that it exists"
            Set-Variable testninjafieldWYSIWYGdrives -Value $false -Scope Global -option ReadOnly -Force
        }
        $testninjafieldWYSIWYGvirtual = Ninja-Property-Get $fieldWYSIWYGvirtual 2>&1
        if ($testninjafieldWYSIWYGvirtual -match "Unable to find the specified field" ){
            Write-Host "Unable to access $fieldWYSIWYGvirtual field in ninja"
            Write-Host "Check permissions of WYSIWYG field and that it exists"
            Set-Variable testninjafieldWYSIWYGvirtual -Value $false -Scope Global -option ReadOnly -Force
        }
        $testninjafieldWYSIWYGstatus = Ninja-Property-Get $fieldWYSIWYGstatus 2>&1
        if ($testninjafieldWYSIWYGstatus -match "Unable to find the specified field" ){
            Write-Host "Unable to access $fieldWYSIWYGstatus field in ninja"
            Write-Host "Check permissions of WYSIWYG field and that it exists"
            Set-Variable testninjafieldWYSIWYGstatus -Value $false -Scope Global -option ReadOnly -Force
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
        [string]$fieldWYSIWYGvirtual        = '',
        [string]$fieldWYSIWYGstatus         = '',
        [string]$fieldraidarraystatus       = '',
        [string]$fieldraidarraydetails      = '',
        [System.Collections.Generic.List[Object]]$resultraidarraydetails     = '',
        [System.Collections.Generic.List[Object]]$resultAllDrives,
        [System.Collections.Generic.List[Object]]$resultAllvirtual,
        [System.Collections.Generic.List[Object]]$resultfaileddrives = ''
    )
    if (-not (Get-Command -Name "Ninja-Property-Set" -ErrorAction SilentlyContinue)) {
        $errorMessage = "Error: NinjaRMM module not found, not writing to NinjaRMM."
        return $errorMessage
    }
    # Set standard Custom fields
    if ($resultraidarraydetails.supported -ne $false) {
        if (($($resultraidarraydetails."VirtualStatus") -eq "Healthy") -and ($($resultraidarraydetails."PhysicalStatus") -eq "Healthy")) {
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
    }
    # Set WYSIWYG Custom fields
    if($resultAllDrives){
        if($testninjafieldWYSIWYGdrives -ne $false){
            Write-Verbose "Will try write $fieldWYSIWYGdrives value"
            $htmlTabledrives = ConvertTo-ObjectToHtmlTable -Objects $resultAllDrives
            $htmlTabledrives | Ninja-Property-Set-Piped -Name $fieldWYSIWYGdrives
        }
    }
    if($resultAllvirtual){
        if($testninjafieldWYSIWYGvirtual -ne $false){
            Write-Verbose "Will try write $fieldWYSIWYGvirtual value"
            $htmlTablevirtual = ConvertTo-ObjectToHtmlTable -Objects $resultAllvirtual
            $htmlTablevirtual | Ninja-Property-Set-Piped -Name $fieldWYSIWYGvirtual
        }
    }
    if($resultraidarraydetails){
        if($testninjafieldWYSIWYGtatus -ne $false){
            Write-Verbose "Will try write $fieldWYSIWYGstatus value"
            $htmlTablestatus  = ConvertTo-ObjectToHtmlTable -Objects $resultraidarraydetails
            $htmlTablestatus  | Ninja-Property-Set-Piped -Name $fieldWYSIWYGstatus 
        }
    }
}

Start-EasyRaidCheck
