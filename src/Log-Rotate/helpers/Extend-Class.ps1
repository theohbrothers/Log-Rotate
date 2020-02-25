# Class Helper - Unused for now
function Extend-Class {
    param ($classObject, [PSModuleInfo]$importedModule)

    $importedModule.ExportedFunctions.Keys | ForEach-Object {
        Write-Verbose "Key: $_"
        Write-Verbose "Function: $((Get-item function:$_).Definition)"
        $scriptblock = [Scriptblock]::Create( (Get-item function:$_).Definition )
        $classObject | Add-Member -Name $_ -MemberType ScriptMethod -Value $scriptblock
    }
}
