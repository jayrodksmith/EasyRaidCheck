function Get-RaidControllerHP {
    [CmdletBinding()]
    param (
    )
if (($PhysicalStatus -eq "Healthy") -and ($RAIDStatus -eq "Healthy")) {
    Write-Host "Raid Status: Healthy"
    Ninja-Property-Set raidarraystatus "Healthy"
    Ninja-Property-Set raidarraydetails $raidarraydetails
    #Write-Host '0'
    exit 0
}
else {
    Write-Host "Raid Status: Not Healthy"
    Ninja-Property-Set raidarraystatus "Not Healthy"
    Ninja-Property-Set raidarraydetails $raidarraydetails
    #Write-Host '999'
    exit 999
}

$htmlTable = ConvertTo-ObjectToHtmlTable -Objects $AllDrives
$htmlTable | Ninja-Property-Set-Piped -Name raidtablephysical
}