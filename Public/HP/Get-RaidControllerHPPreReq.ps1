function Get-RaidControllerHPPreReq {
    [CmdletBinding()]
    param (
        $hpurl = "https://downloads.hpe.com/pub/softlib2/software1/sc-windows/p632700740/v238698/cp044527.exe", # URL for HP CLI
        $hpurl2 = "https://downloads.hpe.com/pub/softlib2/software1/sc-windows/p1394061884/v238699/cp044528.exe",# URL for HP ADU
        $hpoutput = "$($env:windir)\temp\cp044527.exe",
        $hpoutput2 = "$($env:windir)\temp\cp044528.exe",
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
            Start-Process -FilePath $hpoutput -ArgumentList "/s"
            Copy-Item -Path $hpCLILocation -Destination $hpfolder -Force
        }catch{
            Write-Error "An error occurred: $_"
        }
    }else{
        Write-Verbose "HP CLI already installed"
    }
    if (-not(Test-Path -Path $hpLocationadu -PathType Leaf)) {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        try {
            Write-Verbose "HP ADU downloading and installing"
            Invoke-WebRequest -Uri $hpurl2 -OutFile $hpoutput2
            Start-Process -FilePath $hpoutput2 -ArgumentList "/s"
            Copy-Item -Path $hpCLILocation2 -Destination $hpfolder -Force
        }catch{
            Write-Error "An error occurred: $_"
        }
    }else{
        Write-Verbose "HP ADU already installed"
    }
}