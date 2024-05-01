function Write-ResultNinjaRMM {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [string]$fieldWYSIWYGdrives         = '',
        [string]$fieldWYSIWYGvirtual        = '',
        [string]$fieldWYSIWYGstatus         = '',
        [string]$fieldraidarraystatus       = '',
        [string]$fieldraidarraydetails      = '',
        [System.Collections.Generic.List[Object]]$resultraidarraydetails     = '',
        [System.Collections.Generic.List[Object]]$resultAllDrives,
        [System.Collections.Generic.List[Object]]$resultAllvirtual,
        [string]$resultfaileddrives         = ''
    )
    if (-not (Get-Command -Name "Ninja-Property-Set" -ErrorAction SilentlyContinue)) {
        $errorMessage = "Error: NinjaRMM module not found, not writing to NinjaRMM."
        return $errorMessage
    }
    # Set standard Custom fields
    if ($resultraidarraydetails.supported -ne $false) {
        if (($($resultraidarraydetails."VirtualStatus") -eq "Healthy") -and ($($resultraidarraydetails."PhysicalStatus") -eq "Healthy")) {
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
    }
    # Set WYSIWYG Custom fields
    if($resultAllDrives){
        if($testninjafieldWYSIWYGdrives -ne $false){
            Write-Verbose "Will try write $fieldWYSIWYGdrives value"
            $htmlTabledrives = ConvertTo-ObjectToHtmlTable -Objects $resultAllDrives
            $htmlTabledrives | Ninja-Property-Set-Piped -Name $fieldWYSIWYGdrives
            
            Write-Verbose "Will try write $fieldWYSIWYGvirtual value"
            $htmlTablevirtual = ConvertTo-ObjectToHtmlTable -Objects $resultAllvirtual
            $htmlTablevirtual | Ninja-Property-Set-Piped -Name $fieldWYSIWYGvirtual

            Write-Verbose "Will try write $fieldWYSIWYGstatus value"
            $htmlTablestatus  = ConvertTo-ObjectToHtmlTable -Objects $resultraidarraydetails
            $htmlTablestatus  | Ninja-Property-Set-Piped -Name $fieldWYSIWYGstatus 
        }
    }
}