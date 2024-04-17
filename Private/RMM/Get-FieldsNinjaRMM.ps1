function Get-FieldsNinjaRMM {
    <#
        .SYNOPSIS
        Function to get details to NinjaRMM
    
        .DESCRIPTION
        This function will get details to NinjaRMM
    
        .EXAMPLE
        Get-WarrantyNinjaRMM

    #>
        [CmdletBinding(SupportsShouldProcess)]
        param (
            [string]$ninjafieldWYSIWYGdrives    = '',
            [string]$ninjafieldraidarraystatus  = '',
            [string]$ninjafieldraidarraydetails = ''
        )
        # Import Ninja Powershell Module
        Write-Verbose "Importing Ninja Powershell module"
        Import-Module NJCliPSh -ErrorAction SilentlyContinue -WarningAction SilentlyContinue -verbose:$false | Out-Null
        # Test if fields exist
        $testninjafieldWYSIWYGdrives = Ninja-Property-Get $ninjafieldWYSIWYGdrives 2>&1
        if ($testninjafieldWYSIWYGdrives -match "Unable to find the specified field" ){
            Write-Host "Unable to access $ninjafieldWYSIWYGdrives field in ninja"
            Write-Host "Check permissions of field and that it exists"
            Set-Variable testninjafieldWYSIWYGdrives -Value $false -Scope Global -option ReadOnly -Force
        }
        $testninjafieldraidarraystatus  = Ninja-Property-Get $ninjafieldraidarraystatus  2>&1
        if ($testninjafieldraidarraystatus  -match "Unable to find the specified field" ){
            Write-Host "Unable to access $ninjafieldraidarraystatus field in ninja"
            Write-Host "Check permissions of field and that it exists"
            Set-Variable testninjafieldraidarraystatus -Value $false -Scope Global -option ReadOnly -Force
        }
        $testninjafieldraidarraydetails  = Ninja-Property-Get $ninjafieldraidarraydetails  2>&1
        if ($testninjafieldraidarraydetails  -match "Unable to find the specified field" ){
            Write-Host "Unable to access $ninjafieldraidarraydetails field in ninja"
            Write-Host "Check permissions of field and that it exists"
            Set-Variable testninjafieldraidarraydetails -Value $false -Scope Global -option ReadOnly -Force
        }
    }