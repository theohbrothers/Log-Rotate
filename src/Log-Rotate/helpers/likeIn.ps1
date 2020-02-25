function likeIn ([string]$string, [string[]]$wildcardblobs) {
    foreach ($wildcardblob in $wildcardblobs) {
        if ($string -like $wildcardblob) {
            return $true
        }
    }
    $false
}
