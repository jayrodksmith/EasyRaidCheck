function Get-RaidControllers{
    [CmdletBinding()]
    param (
    )

    $controllers = Get-CimInstance -ClassName "Win32_SCSIController"
    $found = $false
    
    # Define controller name patterns for different vendors
    $lsiPatterns = "*lsi*", "*megaraid*", "*Intel(R) Integrated RAID Module*", "*Intel(R) RAID Controller*", "*megasas*", "*Avago*", "*ThinkSystem RAID*", "*PERC*"
    $hpPattern = "*Smart Array*"
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
    return $results, $controllers
}