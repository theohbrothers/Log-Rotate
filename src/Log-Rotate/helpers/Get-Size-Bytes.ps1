function Get-Size-Bytes {
    # Returns a size specified with a unit (E.g. 100, 100k, 100M, 100G) into bytes without a unit
    param (
        [string]$size_str
    )
    if ($g_debugFlag -band 4) { Write-Debug "[Get-Size-Bytes] Verbose stream: $VerbosePreference" }
    if ($g_debugFlag -band 4) { Write-Debug "[Get-Size-Bytes] Debug stream: $DebugPreference" }
    if ($g_debugFlag -band 4) { Write-Debug "[Get-Size-Bytes] Erroraction: $ErrorActionPreference" }

    if ($size_str -match '(?:[0-9]+|[0-9]+(?:k|M|G))$') {
        $size_unit = $size_str -replace '[0-9]+'
        [int64]$size = $size_str -replace $size_unit
        switch($size_unit) {
            "" { $size = $size }
            "k" { $size = $size * 1024 }
            "M" { $size = $size * 1024 * 1024 }
            "G" { $size = $size * 1024 * 1024 * 1024 }
        }
    }else {
        #Write-Error "The size specified was '$size_str'. Size should be specified in quantity and unit, e.g. '100k', or '100M'. Only units 'k', 'M', or 'G' are allowed." -ErrorAction Stop
        throw "The size specified was '$size_str'. Size should be specified in quantity and unit, e.g. '100k', or '100M'. Only units 'k', 'M', or 'G' are allowed."
        #Write-Error -Exception (New-Object Exception "The size specified was '$size_str'. Size should be specified in quantity and unit, e.g. '100k', or '100M'. Only units 'k', 'M', or 'G' are allowed.") -ErrorAction Stop
    }
    $size
}
