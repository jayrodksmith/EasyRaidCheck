function Expand-File{
    [CmdletBinding()]
    param (
        $file,
        $destination,
    )
    Function Test-CommandExists {
        Param (
            $command
        )
        $oldPreference = $ErrorActionPreference
        $ErrorActionPreference = 'stop'
        try {
            if(Get-Command $command){
                return $true
            }
        } Catch {
            Write-Verbose "$command does not exist"
            return $false
        } Finally {
            $ErrorActionPreference=$oldPreference
        }
    }
    if (Test-CommandExists 'Expand-Archive' -eq $True ){
        $commandexist = $True
        } else {
        $commandexist = $False
        }
    if($commandexist -eq $True) {
        Expand-Archive -Path $file -DestinationPath $destination
    } else {
        $shell = new-object -com shell.application
        $zip = $shell.NameSpace($file)
        foreach($item in $zip.items()){
            $shell.Namespace($destination).copyhere($item, 0x14)
        }
    }
}