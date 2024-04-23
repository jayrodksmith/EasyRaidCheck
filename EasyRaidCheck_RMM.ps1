

function Get-RaidControllers{
    [CmdletBinding()]
    param (
    )

    $controllers = Get-CimInstance -ClassName "Win32_SCSIController"
    $found = $false
    
    # Define controller name patterns for different vendors
    $lsiPatterns = "*lsi*", "*megaraid*", "*Intel(R) Integrated RAID Module*", "*Intel(R) RAID Controller*", "*megasas*", "*Avago*", "*ThinkSystem RAID*"
    $percPattern = "*PERC*"
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
        [string]$lsioutput                  = "$($env:windir)\temp\storcli.zip",
        [string]$lsiCLILocation             = 'C:\ProgramData\EasyRaidCheck\LSI\Intel_StorCLI_007.1907.0000.0000\Unified_storcli_all_os\Windows\storcli64.exe',
        # HP Details
        [string]$hpurl                      = "https://downloads.hpe.com/pub/softlib2/software1/sc-windows/p955544928/v183348/cp044527.exe",
        [string]$hpoutput                   = "C:\temp\cp044527.exe", 
        [string]$hpCLILocation              = 'C:\Program Files\Smart Storage Administrator\ssacli\bin\ssacli.exe', # Dont change this, HP tools is a installed program
        # PERC Details
        [string]$percurl                    = "https://raw.githubusercontent.com/jayrodksmith/EasyRaidCheck/main/public/PERC/perccli64.exe",
        [string]$percoutput                 = 'C:\ProgramData\EasyRaidCheck\Dell\perccli64.exe', 
        [string]$percCLILocation            = 'C:\ProgramData\EasyRaidCheck\Dell\perccli64.exe',      
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
        $raidarraydetails, $AllDrives, $faileddrives                                        = Get-RaidControllerHP -ControllerName ($($supportedcontrollers.'Controller Name') | Select-object -first 1)
    } elseif ($supportedcontrollers.'Controller Type' -match "PERC"){
        # HP
        $raidarraydetails, $AllDrives, $faileddrives                                        = Get-RaidControllerPERC -ControllerName ($($supportedcontrollers.'Controller Name') | Select-object -first 1)
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
        $smartalldrives, $smartFailedDrives                                                 = Get-SMARTInfo
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
                    if($drive.'Smart Status' -notmatch '\bGood\b' -and $null -ne $drive.'Smart Status'){
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
        Get-FieldsNinjaRMM -fieldWYSIWYGdrives $ninjafieldWYSIWYGdrives -fieldraidarraystatus $ninjafieldraidarraystatus -fieldraidarraydetails $ninjafieldraidarraydetails
        Write-ResultNinjaRMM -fieldWYSIWYGdrives $ninjafieldWYSIWYGdrives -fieldraidarraystatus $ninjafieldraidarraystatus -fieldraidarraydetails $ninjafieldraidarraydetails -resultraidarraydetails $raidarraydetails -resultAllDrives $AllDrives -resultfaileddrives $faileddrives
    }
    # Output results to screen
    $raidarraydetails | format-table
    if($supported -ne $false) {
        $AllDrives | Select-object Array,DriveNumber,Port,Bay,Status,Reason,Size,Interface,Serial,Model,Temp,'Smart Status' | format-table * -autosize
    } else{
        $AllDrives | format-table * -autosize
    }
    
    if($faileddrives){
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

function Get-RaidControllerHP{
    [CmdletBinding()]
    param (
        [string]$hpCLILocation = 'C:\Program Files\Smart Storage Administrator\ssacli\bin\ssacli.exe',
        [string]$hpCLILocation2 = 'C:\Program Files\Smart Storage Administrator\ssaducli\bin\ssaducli.exe',
        [string]$hpclireport = "C:\temp\HPReport.txt",
        [string]$controllerName = "Unknown"

    )
    
    Get-RaidControllerHPPreReq

    $hpraidstatus = & $hpCLILocation ctrl all show status | Out-String
    $hpraidstatus2 = & $hpCLILocation2 -adu -txt -f $hpclireport

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
        Write-Verbose "Creating object for $PhysicalStatus_drivenumber"
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

function Get-RaidControllerHPPreReq {
    [CmdletBinding()]
    param (
        $hpurl = "https://downloads.hpe.com/pub/softlib2/software1/sc-windows/p955544928/v183348/cp044527.exe", # URL for HP CLI
        $hpurl2 = "https://downloads.hpe.com/pub/softlib2/software1/sc-windows/p2024036775/v183350/cp044528.exe",# URL for HP ADU
        $hpoutput = "C:\temp\cp044527.exe",
        $hpoutput2 = "C:\temp\cp044528.exe",
        $hpCLILocation = 'C:\Program Files\Smart Storage Administrator\ssacli\bin\ssacli.exe',
        $hpCLILocation2 = 'C:\Program Files\Smart Storage Administrator\ssaducli\bin\ssaducli.exe',
        $hpfolder = "C:\ProgramData\EasyRaidCheck\HP"
    )
    if (-not (Test-Path -Path $hpfolder)) {
        # If it doesn't exist, create it
        $newfolder = New-Item -Path $hpfolder -ItemType Directory -erroraction SilentlyContinue | Out-null
    } 
    if (-not(Test-Path -Path $hpCLILocation -PathType Leaf)) {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        try {
            Write-Verbose "HP CLI downloading and installing"
            Invoke-WebRequest -Uri $hpurl -OutFile $hpoutput
            Start-Process -FilePath 'C:\temp\cp044527.exe' -ArgumentList "/s"
        }catch{
            Write-Error "An error occurred: $_"
        }
    }else{
        Write-Verbose "HP CLI already installed"
    }
    if (-not(Test-Path -Path $hpCLILocation2 -PathType Leaf)) {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        try {
            Write-Verbose "HP ADU downloading and installing"
            Invoke-WebRequest -Uri $hpurl2 -OutFile $hpoutput2
            Start-Process -FilePath 'C:\temp\cp044528.exe' -ArgumentList "/s"
        }catch{
            Write-Error "An error occurred: $_"
        }
    }else{
        Write-Verbose "HP ADU already installed"
    }
}

## Intial Code Here

function Get-SMARTInfo {
    param(
        $CDIPath = "C:\temp\ninjarmm\crystaldiskinfo\"
    )
    
    $CDIExecutable = Join-Path -Path $CDIPath -ChildPath 'DiskInfo64.exe'
    Get-SMARTPreReq -crystalLocation $CDIExecutable

    try {
        Start-Process -FilePath $CDIExecutable -ArgumentList '/CopyExit' -Wait
    }
    catch {
        Write-Error "An error occurred: $_"
    }
    
    $warning = $false
    # Define an array to store the drive objects
    $smartalldrives = @()
    $drive = New-Object -TypeName PSObject

    Get-Content (Join-Path -Path $CDIPath -ChildPath 'DiskInfo.txt') | ForEach-Object {
        # Check if the line contains drive information
        if ($_ -match 'Model : (.*)') {
            # Add collected information to the drive object
            $drive | Add-Member -MemberType NoteProperty -Name "Model" -Value $matches[1]
        }
        elseif ($_ -match 'Firmware : (.*)') {
            $drive | Add-Member -MemberType NoteProperty -Name "Firmware" -Value $matches[1]
        }
        elseif ($_ -match 'Serial Number : (.*)') {
            $drive | Add-Member -MemberType NoteProperty -Name "Serial Number" -Value $matches[1]
        }
        elseif ($_ -match 'Interface : (.*)') {
            $drive | Add-Member -MemberType NoteProperty -Name "Interface" -Value $matches[1]
        }
        elseif ($_ -match 'Health Status : (.*)') {
            $drive | Add-Member -MemberType NoteProperty -Name "Health Status" -Value $matches[1]
        }
        elseif ($_ -match 'Power On Hours : (.*)') {
            $drive | Add-Member -MemberType NoteProperty -Name "Power On Hours" -Value $matches[1]
        }
        elseif ($_ -match 'Temperature : (.*)') {
            $drive | Add-Member -MemberType NoteProperty -Name "Temperature" -Value $matches[1]
        }
        # Add other properties similarly
        
        elseif ($_ -match 'Drive Letter : (.*)') {
            # Add the drive letter to the existing drive object
            $drive | Add-Member -MemberType NoteProperty -Name "DriveLetter" -Value $matches[1]

            # Add the completed drive object to the array
            $smartalldrives += $drive

            # Reset the drive object for the next drive
            $drive = New-Object -TypeName PSObject
        }
    }
    # Output the array of drive objects
    $smartFailedDrives = $smartAllDrives | Where-Object { $_."Health Status" -notlike "*Good*" }
    return $smartalldrives, $smartFailedDrives
}


function Get-SMARTPreReq {
    [CmdletBinding()]
    param (
        $crystalurl = "https://ixpeering.dl.sourceforge.net/project/crystaldiskinfo/9.2.3/CrystalDiskInfo9_2_3.zip",
        $crystaloutput = "C:\temp\CrystalDiskInfo.zip",
        $crystalLocation = "C:\temp\ninjarmm\crystaldiskinfo\DiskInfo64.exe",
        $crystalextract = "C:\temp\ninjarmm\crystaldiskinfo"
    )
    if (-not(Test-Path -Path $crystalLocation -PathType Leaf)) {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        try {
            Write-Verbose "Extracting CrystalDiskInfo"
            Invoke-WebRequest -Uri $crystalurl -OutFile $crystaloutput
            Expand-File -File $crystaloutput -Destination $crystalextract
        }catch{
            Write-Error "An error occurred: $_"
        }
    }else{
        Write-Verbose "CrystalDiskInfo already exists"
    }
}

function Get-RaidControllerLSI{
    [CmdletBinding()]
    param (
        [string]$StorCLILocation = 'C:\ProgramData\EasyRaidCheck\LSI\Intel_StorCLI_007.1907.0000.0000\Unified_storcli_all_os\Windows\storcli64.exe',
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

function Get-RaidControllerLSIPreReq {
    [CmdletBinding()]
    param (
        $lsiurl = "https://downloadmirror.intel.com/743783/Intel_StorCLI_007.1907.0000.0000.zip", # URL for StorCLI
        $lsioutput = "$($env:windir)\temp\storcli.zip",
        $lsiCLILocation = 'C:\ProgramData\EasyRaidCheck\LSI\Intel_StorCLI_007.1907.0000.0000\Unified_storcli_all_os\Windows\storcli64.exe',
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
        }catch{
            Write-Error "An error occurred: $_"
        }
    }else{
        Write-Verbose "LSI Tools already exists"
    }
}

function Get-RaidControllerPERC{
    [CmdletBinding()]
    param (
        [string]$percCLILocation = 'C:\ProgramData\EasyRaidCheck\Dell\perccli64.exe',
        [string]$percCliCommandvirtualdrive = "/c0 /vall show j",
        [string]$percCliCommandvirtualdrivegroup = "/c0 /dall show j",
        [string]$percCliCommandphysical = "/c0 /eall /sall show j",
        [string]$percCliCommandphysicalall = "/c0 /eall /sall show all",
        [string]$controllerName = "Unknown"
    )
    
    Get-RaidControllerPERCPreReq
    try {
        $ExecuteStoreCLIvirtualdrive = & $percCLILocation $percCliCommandvirtualdrive | out-string
        $ArrayStorCLIvirtualdrive = ConvertFrom-Json $ExecuteStoreCLIvirtualdrive
        $ExecuteStoreCLIvirtualdrivegroup = & $percCLILocation $percCliCommandvirtualdrivegroup | out-string
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
        $ExecuteStoreCLIphysical = & $percCLILocation $percCliCommandphysical | out-string
        $ArrayStorCLIphysical = ConvertFrom-Json $ExecuteStoreCLIphysical
        $ExecuteStoreCLIphysicalall = & $percCLILocation $percCliCommandphysicalall | out-string
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

function Get-RaidControllerPERCPreReq {
    [CmdletBinding()]
    param (
        $percurl = "https://raw.githubusercontent.com/jayrodksmith/EasyRaidCheck/main/Public/PERC/perccli64.exe", # URL for StorCLI
        $percoutput = "C:\ProgramData\EasyRaidCheck\Dell\perccli64.exe",
        $percCLILocation = "C:\ProgramData\EasyRaidCheck\Dell\perccli64.exe",
        $percfolder = "C:\ProgramData\EasyRaidCheck\Dell"
    )
    # Check if the folder exists
    if (-not (Test-Path -Path $percfolder)) {
        # If it doesn't exist, create it
        $newfolder = New-Item -Path $percfolder -ItemType Directory -erroraction SilentlyContinue | Out-null
    } 
    if (-not(Test-Path -Path $percCLILocation -PathType Leaf)) {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        try {
            Write-Verbose "PERC Tools downloading and extracting"
            Invoke-WebRequest -Uri $percurl -OutFile $percoutput
        }catch{
            Write-Error "An error occurred: $_"
        }
    }else{
        Write-Verbose "PERC Tools already exists"
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
        [System.Collections.Generic.List[Object]]$resultraidarraydetails     = '',
        [System.Collections.Generic.List[Object]]$resultAllDrives,
        [string]$resultfaileddrives         = ''
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
            Write-Verbose "Will try write WYSIWYGdrives value"
            $htmlTable = ConvertTo-ObjectToHtmlTable -Objects $resultAllDrives
            $htmlTable | Ninja-Property-Set-Piped -Name $fieldWYSIWYGdrives
        }
    }
}

## Intial Code Here

Start-EasyRaidCheck
