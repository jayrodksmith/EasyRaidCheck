function Get-RaidControllerVROCPreReq {
    [CmdletBinding()]
    param (
        $vrocurl = "https://raw.githubusercontent.com/jayrodksmith/EasyRaidCheck/main/Public/VROC/IntelVROCCli.exe", # URL for IntelVROCCli
        $vrocLocation = "",
        $vrocfolder = "C:\ProgramData\EasyRaidCheck\VROC"
    )
    # Check if the folder exists
    if (-not (Test-Path -Path $vrocfolder)) {
        # If it doesn't exist, create it
        $newfolder = New-Item -Path $vrocfolder -ItemType Directory -erroraction SilentlyContinue | Out-null
    } 
    if (-not(Test-Path -Path $vrocLocation -PathType Leaf)) {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        try {
            Write-Verbose "VROC Tools downloading and extracting"
            Invoke-WebRequest -Uri $vrocurl -OutFile $vrocLocation
        }catch{
            Write-Error "An error occurred: $_"
            exit 888
        }
    }else{
        Write-Verbose "VROC Tools already exists"
    }
}