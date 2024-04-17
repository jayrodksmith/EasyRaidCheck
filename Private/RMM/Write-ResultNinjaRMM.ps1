function Write-ResultNinjaRMM {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [string]$fieldWYSIWYGdrives         = '',
        [string]$fieldraidarraystatus       = '',
        [string]$fieldraidarraydetails      = '',
        [string]$resultraidarraydetails     = '',
        [System.Collections.Generic.List[Object]]$resultAllDrives,
        [string]$resultfaileddrives         = ''
    )
    if (-not (Get-Command -Name "Ninja-Property-Set" -ErrorAction SilentlyContinue)) {
        $errorMessage = "Error: NinjaRMM module not found, not writing to NinjaRMM."
        return $errorMessage
    }
    # Set standard Custom fields
    if (($raidarraydetails."VirtualStatus" -eq "Healthy") -and ($raidarraydetails."PhysicalStatus" -eq "Healthy")) {
        if($testninjafieldraidarraystatus -ne $false){
            Write-Verbose "Will try write raidarraystatus value"
            Ninja-Property-Set $fieldraidarraystatus "Healthy"
        }
        if($testninjafieldraidarraydetails -ne $false){
            Write-Verbose "Will try write raidarraydetails value"
            $resultraidarraydetails | Ninja-Property-Set-Piped -Name $fieldraidarraydetails
        }
    } else {
        if($testninjafieldraidarraystatus -ne $false){
            Write-Verbose "Will try write raidarraystatus value"
            Ninja-Property-Set $fieldraidarraystatus "Not Healthy"
        }
        if($testninjafieldraidarraydetails -ne $false){
            Write-Verbose "Will try write raidarraydetails value"
            $resultraidarraydetails | Ninja-Property-Set-Piped -Name $fieldraidarraydetails
        }
    }
    # Set WYSIWYG Custom fields
    if($resultAllDrives){
        if($testninjafieldWYSIWYGdrives -ne $false){
            Write-Verbose "Will try write WYSIWYGdrives value"
            $htmlTable = ConvertTo-ObjectToHtmlTable -Objects $resultAllDrives
            $htmlTable | Ninja-Property-Set-Piped -Name $fieldWYSIWYGdrives
        }
    }
}