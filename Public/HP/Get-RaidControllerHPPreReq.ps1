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