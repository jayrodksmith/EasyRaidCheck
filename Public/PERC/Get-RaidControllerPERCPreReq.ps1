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