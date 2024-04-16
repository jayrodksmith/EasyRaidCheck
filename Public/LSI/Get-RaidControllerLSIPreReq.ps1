function Get-RaidControllerLSIPreReq {
    [CmdletBinding()]
    param (
        $lsiurl = "https://downloadmirror.intel.com/743783/Intel_StorCLI_007.1907.0000.0000.zip", # URL for StorCLI
        $lsioutput = "C:\temp\storcli.zip",
        $lsiCLILocation = 'C:\temp\Intel_StorCLI_007.1907.0000.0000\Unified_storcli_all_os\Windows\storcli64.exe'
    )
    if (-not(Test-Path -Path $lsiCLILocation -PathType Leaf)) {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        try {
            Write-Verbose "LSI Tools downloading and extracting"
            Invoke-WebRequest -Uri $lsiurl -OutFile $lsioutput
            Expand-File -File $lsioutput -Destination "C:\temp"
        }catch{
            Write-Error "An error occurred: $_"
        }
    }else{
        Write-Verbose "LSI Tools already exists"
    }
}