function Get-SMARTInfo {
    param(
        $CDIPath = ""
    )
    
    $CDIExecutable = $CDIPath
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
