function Get-RaidControllers{
    [CmdletBinding()]
    param (
    )

    $controllers = Get-CimInstance -ClassName "Win32_SCSIController"
    $found = $false
    
    # Define controller name patterns for different vendors
    $lsiPatterns = "*lsi*", "*megaraid*", "*Intel(R) Integrated RAID Module*", "*Intel(R) RAID Controller*", "*Intel Embedded Server RAID Technology II*","*ServeRAID*", "*megasas*", "*Avago*","*Lenovo ThinkServer RAID*", "*ThinkSystem RAID*", "*Asustek pike 2208*", "*ASUSTEK PIKE II*","*Intel(R) Integrated RAID RS3*", "*SAS3008*","*SAS3108*","*SAS2208*","*Gigabyte MR-3108*","*MSI S101B IMR*","*SAS3004*","*ASRR_M3108*"
    $percPattern = "*PERC*"
    $hpPattern = "*Smart Array*", "*Adaptec SmartHBA-SA*", "*Microchip Adaptec HBA 1000*"
    $vrocPattern = "*VROC*"
    $results = @() # Initialize an empty array to store results

    # Find LSI
    foreach ($controller in $controllers) {
        foreach ($pattern in $lsiPatterns) {
            if ($controller.Name -like $pattern) {
                $results += [PSCustomObject]@{
                    "Controller Name" = $controller.Name
                    "Controller Type" = "LSI"
                }
                $found = $true
            }
        }
    }
    # Find HP
    foreach ($controller in $controllers) {
        foreach ($pattern in $hpPattern) {
            if ($controller.Name -like $pattern) {
                $results += [PSCustomObject]@{
                    "Controller Name" = $controller.Name
                    "Controller Type" = "HP"
                }
                $found = $true
            }
        }
    }
    # Find PERC
    foreach ($controller in $controllers) {
        foreach ($pattern in $percPattern) {
            if ($controller.Name -like $pattern) {
                $results += [PSCustomObject]@{
                    "Controller Name" = $controller.Name
                    "Controller Type" = "PERC"
                }
                $found = $true
            }
        }
    }
    # Find VROC
    foreach ($controller in $controllers) {
        foreach ($pattern in $vrocPattern) {
            if ($controller.DriverName -like $pattern) {
                $results += [PSCustomObject]@{
                    "Controller Name" = $controller.Name
                    "Controller Type" = "VROC"
                }
                $found = $true
            }
        }
    }         
    return $results, $controllers
}