

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
        $raidarraydetails, $AllDrives, $virtualdrives, $faileddrives                                        = Get-RaidControllerHP -hpCLIlocation $ssacli -hpADUlocation $ssaducli -ControllerName ($($supportedcontrollers.'Controller Name') | Select-object -first 1)
    } elseif ($supportedcontrollers.'Controller Type' -match "PERC"){
        # PERC
        $raidarraydetails, $AllDrives, $virtualdrives, $faileddrives, $FailedVirtualDrives, $MissingDrives  = Get-RaidControllerPERC -percCLILocation $perccli64 -ControllerName ($($supportedcontrollers.'Controller Name') | Select-object -first 1)
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
        $smartalldrives, $smartFailedDrives = Get-SMARTInfo -CDIPath $DiskInfo64
        # Check existing results and merge results if found.
        if ($supported -ne $false){
            foreach ($drive in $alldrives) {
                $serial = $($drive.Serial)
                $smartDrive = $smartalldrives | Where-Object { $_.'Serial Number' -match $serial }
                if ($smartDrive) {
                    # Merge existing fields from $smartalldrives into $alldrives and set danger flag if required
                    $drive.'Smart Status'       = $($smartDrive.'Health Status')
                    $drive.'Power On Hours'     = $($smartDrive.'Power On Hours')
                    $drive.'DriveLetter'       = $($smartDrive.'Driver Letter')
                    if($null -eq $drive.'Temp'){
                        $drive.'Temp' = $($smartDrive.'Temperature')
                    }
                    if($null -eq $drive.'Size'){
                        $drive.'Size' = $($smartDrive.'Disk Size')
                    }
                    if($null -eq $drive.'Model'){
                        $drive.'Model' = $($smartDrive.'Model')
                    }
                    $percentage = [regex]::Match($drive.'Smart Status', '\((\d+)\s*%\)').Groups[1].Value
                    if($drive.'Smart Status' -notmatch '\bGood\b' -and $null -ne $drive.'Smart Status' -and $drive.'Smart Status' -notmatch '\bUnknown\b'){
                        $drive.'RowColour' = 'danger'
                    }
                } else {
                    # Add non-matching drive to $alldrives with specified properties
                    $newDrive = [PSCustomObject]@{
                        'Size'              = $drive.'Size' 
                        'Interface'         = $drive.'Interface' 
                        'Serial'            = $drive.'Serial'
                        'Model'             = $drive.'Model' 
                        'Temp'              = $drive.'Temperature'
                        'Power On Hours'    = $drive.'Power On Hours'
                        'Smart Status'      = $drive.'Health Status'
                        'DriveLetter'       = $drive.'Drive Letter'
                        'RowColour'         = $drive.'RowColour'
                    }
                    $alldrives += $newDrive
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

function Get-RaidControllerLSI{
    [CmdletBinding()]
    param (
        [string]$StorCLILocation = 'C:\ProgramData\EasyRaidCheck\LSI\storcli64.exe',
        [string]$StorCliCommandvirtualdrive = "/c0 /vall show j",
        [string]$StorCliCommandvirtualdrivegroup = "/c0 /dall show j",
        [string]$StorCliCommandphysical = "/c0 /eall /sall show j",
        [string]$StorCliCommandphysicalall = "/c0 /eall /sall show all",
        [string]$StorCliCommandbasicinfo = "show all",
        [string]$StorCliCommandbasicinfo2 = "/c0 show",
        [string]$StorCliCommandrebuildprogress = "/c0 /eall /sall show rebuild",
        [string]$controllerName = "Unknown"
    )
    
    Get-RaidControllerLSIPreReq -lsiCLILocation $StorCLILocation
    try {
        $ExecuteStorCLIvirtualdrive             = & $StorCLILocation $StorCliCommandvirtualdrive | out-string
        $ArrayStorCLIvirtualdrive               = ConvertFrom-Json $ExecuteStorCLIvirtualdrive
        $ExecuteStorCLIvirtualdrivegroup        = & $StorCLILocation $StorCliCommandvirtualdrivegroup | out-string
        $ArrayStorCLIvirtualdrivegroup          = ConvertFrom-Json $ExecuteStorCLIvirtualdrivegroup
        $ExecuteStorCliCommandbasicinfo         = & $StorCLILocation $StorCliCommandbasicinfo
        $ExecuteStorCliCommandbasicinfo2        = & $StorCLILocation $StorCliCommandbasicinfo2
        $ExecuteStorCliCommandrebuildprogress   = & $StorCLILocation $StorCliCommandrebuildprogress
        } catch {
            $ScriptError = "StorCli Command has Failed: $($_.Exception.Message)"
            exit
        }
    # Get number of controllers
    $LSIcontrollercount     = $ExecuteStorCliCommandbasicinfo  | Select-String -Pattern "Number of Controllers\s*=\s*(\d+)" | ForEach-Object { $_.Matches.Groups[1].Value }
    $LSIcontrollermodel     = $ExecuteStorCliCommandbasicinfo2 | Select-String -Pattern "Product Name\s*=\s*(.*)" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() }
    $LSIcontrollerserial    = $ExecuteStorCliCommandbasicinfo2 | Select-String -Pattern "Serial Number\s*=\s*(.*)" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() }
    $LSIcontrollerfirmware  = $ExecuteStorCliCommandbasicinfo2 | Select-String -Pattern "FW Version\s*=\s*(.*)" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() }
    $LSIcontrollerdriver    = $ExecuteStorCliCommandbasicinfo2 | Select-String -Pattern "Driver Version\s*=\s*(.*)" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() }

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
        $ExecuteStorCLIphysical = & $StorCLILocation $StorCliCommandphysical | out-string
        $ArrayStorCLIphysical = ConvertFrom-Json $ExecuteStorCLIphysical
        $ExecuteStorCLIphysicalall = & $StorCLILocation $StorCliCommandphysicalall | out-string
        # Convert the multiline string to an array of strings by splitting on new lines
        $driveEntries = $ExecuteStorCLIphysicalall -split [System.Environment]::NewLine

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
            'DriveLetter'       = $null
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
    $lines = $ExecuteStorCliCommandrebuildprogress -split "\r?\n"
    # Extract progress and estimated time left from relevant lines
    $lines | Where-Object {$_ -notmatch "Not in progress"} | ForEach-Object {
        if ($_ -match "(\d+)\s+In progress\s+(.+)$") {
            $rebuildpercentage = $matches[1] + " %"
            $estimatedTimeLeft = $matches[2]
        }
    }

    $raidarraydetails = New-Object System.Collections.Generic.List[Object]
    $raidarraydetails.Add([PSCustomObject]@{
        Controller              = $LSIcontrollermodel
        ControllerCount         = $LSIcontrollercount
        'Rebuild Status'        = if($rebuildpercentage){$rebuildpercentage}else{"Not Rebuilding"}
        'Rebuild Remaining'     = if($estimatedTimeLeft){$estimatedTimeLeft}else{"Not Rebuilding"}
        ReadAhead               = $virtualdrives.ReadAhead | Select-Object -First 1
        WriteBack               = $virtualdrives.WriteBack | Select-Object -First 1
        VirtualStatus           = $RAIDStatus
        PhysicalStatus          = $RAIDphysicalstatus
        RowColour               = if (($RAIDStatus -eq 'Not Healthy') -or ($RAIDphysicalstatus -eq 'Not Healthy')) {"danger"}elseif ($rebuildpercentage) {'warning'}else{"success"}
    })
    
    return $raidarraydetails, $AllDrives, $virtualdrives, $FailedDrives, $FailedVirtualDrives, $MissingDrives
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
            'DriveLetter'       = $null
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
        'Rebuild Status'        = if($rebuildpercentage){$rebuildpercentage}else{"Not Rebuilding"}
        'Rebuild Remaining'     = if($estimatedTimeLeft){$estimatedTimeLeft}else{"Not Rebuilding"}
        ReadAhead               = $virtualdrives.ReadAhead | Select-Object -First 1
        WriteBack               = $virtualdrives.WriteBack | Select-Object -First 1
        VirtualStatus           = $RAIDStatus
        PhysicalStatus          = $RAIDphysicalstatus
        RowColour               = if (($RAIDStatus -eq 'Not Healthy') -or ($RAIDphysicalstatus -eq 'Not Healthy')) {"danger"}elseif ($rebuildpercentage) {'warning'}else{"success"}
    })
    
    return $raidarraydetails, $AllDrives, $virtualdrives, $FailedDrives, $FailedVirtualDrives, $MissingDrives
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
