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