function Start-EasyRaidCheck{
    [CmdletBinding()]
    param (
        [string]$RMM                        = 'NinjaOne',
        # Ninja Custom Fields
        [string]$ninjafieldtable            = 'raidtable',
        [string]$ninjafieldraidarraystatus  = 'raidarraystatus',
        [string]$ninjafieldraidarraydetails = 'raidarraydetails',
        # LSI Details
        [string]$lsiCLILocation             = 'C:\temp\Intel_StorCLI_007.1907.0000.0000\Unified_storcli_all_os\Windows\storcli64.exe',
        [string]$lsioutput                  = "C:\temp\storcli.zip",
        [string]$lsiurl                     = "https://downloadmirror.intel.com/743783/Intel_StorCLI_007.1907.0000.0000.zip",
        # HP Details
        [string]$hpurl                      = "https://downloads.hpe.com/pub/softlib2/software1/sc-windows/p955544928/v183348/cp044527.exe",
        [string]$hpoutput                   = "C:\temp\cp044527.exe",
        [string]$hpCLILocation              = 'C:\Program Files\Smart Storage Administrator\ssacli\bin\ssacli.exe' # Dont change this, HP tools is a installed program

    )
$results, $controllers = Get-RaidControllers

}