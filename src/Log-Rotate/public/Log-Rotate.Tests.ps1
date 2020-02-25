$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
. "$here\$sut"

Describe "Log-Rotate" {

    $drive = 'TestDrive:\'

    $logDir = Join-Path $drive 'logs'
    $logFile = Join-Path $logDir 'foo.log'
    $logFileContent = 'foo-bar'

    $configDir = Join-Path $drive 'config'
    $configFile = Join-Path $configDir 'logrotate.conf'
    $configFileContent = @"
"$logFile" {
    rotate 3
    size 1
}
"@

    $stateDir = Join-Path $drive 'state'
    $stateFile = Join-Path $stateDir 'Log-Rotate.status'

    function Init  {
        New-Item $configDir -ItemType Directory -Force > $null
        New-Item $configFile -ItemType File -Force > $null
        $configFileContent | Out-File $configFile -Encoding utf8 -Force

        New-Item $logDir -ItemType Directory -Force > $null
        New-Item $logFile -ItemType File -Force > $null
        $logFileContent | Out-File $logFile -Encoding utf8 -Force

        New-Item $stateDir -ItemType Directory -Force > $null
    }
    function Cleanup  {
        Remove-Item $logDir -Recurse -Force
        Remove-Item $configDir -Recurse -Force
        Remove-Item $stateDir -Recurse -Force
    }

    function Get-Exception-Message ($ErrorRecord) {
        # Recurses to get the innermost exception message
        function Get-InnerExceptionMessage ($Exception) {
            if ($Exception.InnerException) {
                Get-InnerExceptionMessage $Exception.InnerException
            }else {
                $Exception.Message
            }
        }
        $Message = Get-InnerExceptionMessage $ErrorRecord.Exception
        $Message
    }
    function Compile-Full-Config {}
    function Validate-Full-Config {}
    $BlockFactory = [PSCustomObject]@{}
    $BlockFactory | Add-Member -Name 'Create' -MemberType ScriptMethod -Value {}
    $BlockFactory | Add-Member -Name 'GetAll' -MemberType ScriptMethod -Value {
        @{
            '/path/to/foo/bar/' = @{
                'LogFiles' = @()
                'Options' = @()
            }
        }
    }
    $LogFactory = [PSCustomObject]@{}
    $LogFactory | Add-Member -Name 'InitStatus' -MemberType ScriptMethod -Value {
        param ( $State )
        New-Item $State -ItemType File -Force > $null
    }
    $LogFactory | Add-Member -Name 'DumpStatus' -MemberType ScriptMethod -Value {}
    function Process-Local-Block {}

    Context 'Invalid parameters (Non-Terminating)' {

        $eaPreference = 'Continue'

        It 'errors when config is null' {
            Init
            $invalidConfig = $null

            Log-Rotate -Config $invalidConfig -ErrorVariable err -ErrorAction $eaPreference 2>$null
            $err | % { $_.Exception.Message } | Should -Contain "No config file(s) specified."

            Cleanup
        }

        It 'errors when config is an non-existing file' {
            Init
            $invalidConfig = "$configDir/foo"

            Log-Rotate -Config $invalidConfig -ErrorVariable err -ErrorAction $eaPreference 2>$null
            $err | % { $_.Exception.Message } | Should -Contain "Invalid config path specified: $invalidConfig"

            Cleanup
        }

        It 'errors when configAsString is null' {
            Init

            $invalidConfigAsString = $null

            Log-Rotate -ConfigAsString $invalidConfigAsString -ErrorVariable err -ErrorAction $eaPreference 2>$null
            $err | % { $_.Exception.Message } | Should -Contain "No config file(s) specified."

            Cleanup
        }

        It 'errors when state is empty' {
            Init

            $invalidStateFile = $null

            Log-Rotate -config $configFile -State $invalidStateFile -ErrorVariable err -ErrorAction $eaPreference 2>$null
            $err.Count | Should -Not -Be 0

            Cleanup
        }

    }

    Context 'Invalid parameters (Terminating)' {

        $eaPreference = 'Stop'

        It 'errors when config is null' {
            Init
            $invalidConfig = $null

            { Log-Rotate -Config $invalidConfig -ErrorVariable err -ErrorAction $eaPreference } | Should -Throw "No config file(s) specified."

            Cleanup
        }

        It 'errors when config is an non-existing file' {
            Init
            $invalidConfig = "$configDir/foo"

            { Log-Rotate -Config $invalidConfig -ErrorVariable err -ErrorAction $eaPreference } | Should -Throw "Invalid config path specified: $invalidConfig"

            Cleanup
        }

        It 'errors when configAsString is null' {
            Init

            $invalidConfigAsString = $null

            { Log-Rotate -ConfigAsString $invalidConfigAsString -ErrorVariable err -ErrorAction $eaPreference } | Should -Throw "No config file(s) specified."

            Cleanup
        }

        It 'errors when state is empty' {
            Init

            $invalidStateFile = $null

            { Log-Rotate -config $configFile -State $invalidStateFile -ErrorVariable err -ErrorAction $eaPreference } | Should -Throw "Cannot bind argument to parameter 'Path' because it is an empty string."

            Cleanup
        }

    }

    Context 'Functionality' {

        $eaPreference =  'Stop'

        It 'Shows the version' {
            $version = Log-Rotate -Version -ErrorAction $eaPreference

            $version | Should -Match '\d+\.\d+\.\d+$'
        }

        It 'Shows the help' {
            $help = Log-Rotate -Help -ErrorAction $eaPreference

            $help | Should -Not -Be $null
        }

        It 'Compiles configuration' {
            Init

            Mock Compile-Full-Config {}

            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference

            Assert-MockCalled Compile-Full-Config -Times 1

            Cleanup
        }

        It 'Validates configuration' {
            Init

            Mock Validate-Full-Config {}

            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference

            Assert-MockCalled Validate-Full-Config -Times 1

            Cleanup
        }

        It 'Creates block objects from configuration' {
            Init

            $BlockFactory = [PSCustomObject]@{}
            $BlockFactory | Add-Member -Name 'Create' -MemberType ScriptMethod -Value {
                'create'
            }
            $BlockFactory | Add-Member -Name 'GetAll' -MemberType ScriptMethod -Value {
                @{}
            }

            $result = Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference

            $result | Should -Be 'create'
        }

        It 'Initializes the rotation state file' {
            Init

            $LogFactory = [PSCustomObject]@{}
            $LogFactory | Add-Member -Name 'InitStatus' -MemberType ScriptMethod -Value {
                'initstatus'
            }
            $LogFactory | Add-Member -Name 'DumpStatus' -MemberType ScriptMethod -Value {}

            $result = Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference

            $result | Should -Be 'initstatus'
        }

        It 'Processes a block configuration' {
            Init

            Mock Process-Local-Block {}

            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference

            Assert-MockCalled Process-Local-Block -Times 1

            Cleanup
        }

        It 'Dumps the rotation state file' {
            Init

            $LogFactory = [PSCustomObject]@{}
            $LogFactory | Add-Member -Name 'InitStatus' -MemberType ScriptMethod -Value {}
            $LogFactory | Add-Member -Name 'DumpStatus' -MemberType ScriptMethod -Value {
                'dumpstatus'
            }

            $result = Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference

            $result | Should -Be 'dumpstatus'
        }
    }

}
