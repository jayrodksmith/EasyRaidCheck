function Get-RaidControllerPERCPreReq {
    [CmdletBinding()]
    param (
        $percurl = "https://raw.githubusercontent.com/jayrodksmith/EasyRaidCheck/main/public/PERC/perccli64.exe", # URL for StorCLI
        $percoutput = "C:\ProgramData\EasyRaidCheck\Dell\perccli64.exe",
        $percCLILocation = "C:\ProgramData\EasyRaidCheck\Dell\perccli64.exe",
        $percfolder = "C:\ProgramData\EasyRaidCheck\Dell"
    )

    # Check if the folder exists
    if (-not (Test-Path -Path $percfolder)) {
        # If it doesn't exist, create it
        New-Item -Path $percfolder -ItemType Directory
        Write-Output "Folder created at $folderPath"
    } else {
        Write-Output "Folder already exists at $folderPath"
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