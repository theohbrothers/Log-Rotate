param (
    [string]$Tag = ''
)
$MODULE_NAME = (Get-Item $PSScriptRoot/../).Name
$MODULE_DIR = "$PSScriptRoot/../src/$MODULE_NAME"
$MODULE_PATH = "$MODULE_DIR/$MODULE_NAME.psm1"

Set-StrictMode -Version Latest
$global:PesterDebugPreference_ShowFullErrors = $true

# Install Pester if needed
$pester = Get-Module Pester -ListAvailable -ErrorAction SilentlyContinue
$pesterMinVersion = [version]'4.0.0'
$pesterMaxVersion = [version]'4.10.1'
if ( ! $pester -or ! ($pester.Version | ? { $_ -ge $pesterMinVersion -and $_ -le $pesterMaxVersion }) ) {
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        Install-Module Pester -Force -Scope CurrentUser -MinimumVersion $pesterMinVersion -MaximumVersion $pesterMaxVersion -ErrorAction Stop
    }else {
        Install-Module Pester -Force -Scope CurrentUser -MinimumVersion $pesterMinVersion -MaximumVersion $pesterMaxVersion -SkipPublisherCheck -ErrorAction Stop
    }
}
Get-Module Pester -ListAvailable
Import-Module Pester -MinimumVersion $pesterMinVersion -MaximumVersion $pesterMaxVersion -Force -ErrorAction Stop

# Import our module
Get-Module "$MODULE_NAME" | Remove-Module -Force
Import-Module $MODULE_PATH -Force -ErrorAction Stop

if ($Tag) {
    # Run Unit Tests
    $res = Invoke-Pester -Script $MODULE_DIR -Tag $Tag -PassThru -ErrorAction Stop
    if ($res.FailedCount -gt 0) {
        "$( $res.FailedCount ) $Tag tests failed." | Write-Host
    }
    if ($res -and $res.FailedCount -gt 0) {
        throw
    }
}else {
    # Run Unit Tests
    $res = Invoke-Pester -Script $MODULE_DIR -Tag 'Unit' -PassThru -ErrorAction Stop
    if ($res.FailedCount -gt 0) {
        "$( $res.FailedCount ) unit tests failed." | Write-Host
    }

    # Run Integration Tests
    $res2 = Invoke-Pester -Script $MODULE_DIR -Tag 'Integration' -PassThru -ErrorAction Stop
    if ($res2.FailedCount -gt 0) {
        "$( $res2.FailedCount ) integration tests failed." | Write-Host
    }

    if ($res -and $res.FailedCount -gt 0 -or $res2 -and $res2.FailedCount) {
        throw
    }
}
