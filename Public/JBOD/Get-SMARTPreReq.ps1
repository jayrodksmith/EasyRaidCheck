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