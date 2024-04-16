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