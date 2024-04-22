function Get-RaidControllerLSIPreReq {
    [CmdletBinding()]
    param (
        $lsiurl = "https://downloadmirror.intel.com/743783/Intel_StorCLI_007.1907.0000.0000.zip", # URL for StorCLI
        $lsioutput = "$($env:windir)\temp\storcli.zip",
        $lsiCLILocation = 'C:\ProgramData\EasyRaidCheck\LSI\Intel_StorCLI_007.1907.0000.0000\Unified_storcli_all_os\Windows\storcli64.exe',
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
        }catch{
            Write-Error "An error occurred: $_"
        }
    }else{
        Write-Verbose "LSI Tools already exists"
    }
}