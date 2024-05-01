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
            [string]$fieldWYSIWYGdrives    = '',
            [string]$fieldWYSIWYGvirtual   = '',
            [string]$fieldWYSIWYGstatus    = '',
            [string]$fieldraidarraystatus  = '',
            [string]$fieldraidarraydetails = ''
        )
        # Import Ninja Powershell Module
        Write-Verbose "Importing Ninja Powershell module"
        Import-Module NJCliPSh -ErrorAction SilentlyContinue -WarningAction SilentlyContinue -verbose:$false | Out-Null
        # Test if fields exist
        $testninjafieldWYSIWYGdrives = Ninja-Property-Get $fieldWYSIWYGdrives 2>&1
        if ($testninjafieldWYSIWYGdrives -match "Unable to find the specified field" ){
            Write-Host "Unable to access $fieldWYSIWYGdrives field in ninja"
            Write-Host "Check permissions of WYSIWYG field and that it exists"
            Set-Variable testninjafieldWYSIWYGdrives -Value $false -Scope Global -option ReadOnly -Force
        }
        $testninjafieldWYSIWYGvirtual = Ninja-Property-Get $fieldWYSIWYGvirtual 2>&1
        if ($testninjafieldWYSIWYGvirtual -match "Unable to find the specified field" ){
            Write-Host "Unable to access $fieldWYSIWYGvirtual field in ninja"
            Write-Host "Check permissions of WYSIWYG field and that it exists"
            Set-Variable testninjafieldWYSIWYGvirtual -Value $false -Scope Global -option ReadOnly -Force
        }
        $testninjafieldWYSIWYGstatus = Ninja-Property-Get $fieldWYSIWYGstatus 2>&1
        if ($testninjafieldWYSIWYGstatus -match "Unable to find the specified field" ){
            Write-Host "Unable to access $fieldWYSIWYGstatus field in ninja"
            Write-Host "Check permissions of WYSIWYG field and that it exists"
            Set-Variable testninjafieldWYSIWYGstatus -Value $false -Scope Global -option ReadOnly -Force
        }
        $testninjafieldraidarraystatus  = Ninja-Property-Get $fieldraidarraystatus  2>&1
        if ($testninjafieldraidarraystatus  -match "Unable to find the specified field" ){
            Write-Host "Unable to access $fieldraidarraystatus field in ninja"
            Write-Host "Check permissions of field and that it exists"
            Set-Variable testninjafieldraidarraystatus -Value $false -Scope Global -option ReadOnly -Force
        }
        $testninjafieldraidarraydetails  = Ninja-Property-Get $fieldraidarraydetails  2>&1
        if ($testninjafieldraidarraydetails  -match "Unable to find the specified field" ){
            Write-Host "Unable to access $fieldraidarraydetails field in ninja"
            Write-Host "Check permissions of field and that it exists"
            Set-Variable testninjafieldraidarraydetails -Value $false -Scope Global -option ReadOnly -Force
        }
    }