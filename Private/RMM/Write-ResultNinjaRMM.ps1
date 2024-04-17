function Write-ResultNinjaRMM {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [string]$ninjafieldWYSIWYGdrives    = '',
        [string]$ninjafieldraidarraystatus  = '',
        [string]$ninjafieldraidarraydetails = '',
        [string]$raidarraydetails           = '',
        [string]$AllDrives                  = '',
        [string]$faileddrives               = ''
    )
    if (-not (Get-Command -Name "Ninja-Property-Set" -ErrorAction SilentlyContinue)) {
        $errorMessage = "Error: NinjaRMM module not found, not writing to NinjaRMM."
        return $errorMessage
    }
    # Set standard Custom fields
    if (($raidarraydetails."VirtualStatus" -eq "Healthy") -and ($raidarraydetails."PhysicalStatus" -eq "Healthy")) {
        if($testninjafieldraidarraystatus -ne $false){
            Write-Verbose "Will try write raidarraystatus value"
            Ninja-Property-Set $ninjafieldraidarraystatus "Healthy"
        }
        if($testninjafieldraidarraydetails -ne $false){
            Write-Verbose "Will try write raidarraydetails value"
            $raidarraydetails | Ninja-Property-Set-Piped -Name $ninjafieldraidarraydetails
        }
    } else {
        if($testninjafieldraidarraystatus -ne $false){
            Write-Verbose "Will try write raidarraystatus value"
            Ninja-Property-Set $ninjafieldraidarraystatus "Not Healthy"
        }
        if($testninjafieldraidarraydetails -ne $false){
            Write-Verbose "Will try write raidarraydetails value"
            $raidarraydetails | Ninja-Property-Set-Piped -Name $ninjafieldraidarraydetails
        }
    }
    # Set WYSIWYG Custom fields
    if($AllDrives){
        if($testninjafieldWYSIWYGdrives -ne $false){
            Write-Verbose "Will try write WYSIWYGdrives value"
            $htmlTable = ConvertTo-ObjectToHtmlTable -Objects $AllDrives
            $htmlTable | Ninja-Property-Set-Piped -Name $ninjafieldWYSIWYGdrives
        }
    }
}