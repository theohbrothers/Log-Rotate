$MODULE_BASE_DIR = Split-Path $MyInvocation.MyCommand.Path -Parent

Get-ChildItem "$MODULE_BASE_DIR/classes/*.ps1" -exclude *.Tests.ps1 | % {
    . $_.FullName
}

Get-ChildItem "$MODULE_BASE_DIR/helpers/*.ps1" -exclude *.Tests.ps1 | % {
    . $_.FullName
}

Get-ChildItem "$MODULE_BASE_DIR/private/" -recurse | ? { $_.Extension -eq '.ps1' -and $_.Name -notlike '*.Tests.ps1' } | % {
    . $_.FullName
}

Get-ChildItem "$MODULE_BASE_DIR/public/*.ps1" -exclude *.Tests.ps1 | % {
    . $_.FullName
}
