function Test-FormattedTableWidth {
    # Example
    # Test-FormattedTableWidth -Object $object -Width 114
    # Checks if table is larger than 114 characters, which Ninja's Limit is on the console view
    param (
        [Parameter(Mandatory = $true)]
        [psobject]$Object,
        
        [int]$Width = 114
    )

    # Format the object as a table and output it as a string with the specified width
    $formattedOutput = $Object | Format-Table | Out-String -Width $Width

    # Measure the width of the formatted output
    $maxWidth = ($formattedOutput -split "`n" | ForEach-Object { $_.Length }) | Measure-Object -Maximum
    return $maxWidth.Maximum -gt $Width
}