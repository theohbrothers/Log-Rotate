$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
. "$here\$sut"

Describe "Log-Rotate" -Tag 'Unit' {
    $initScriptblock = {
        $configFile = 'foo'

        Mock Test-Path { $true }
        Mock Test-Path -ParameterFilter { $Path -eq 'foo' -and !$PathType } { $true }
        Mock Get-Item { [pscustomobject]@{ FullName = 'foo' } }
        Mock Test-Path -ParameterFilter { $Path -eq 'foo' -and $PathType } { $false }
        Mock Get-ChildItem {}
        Mock Get-Content {}
        function Compile-Full-Config {}
        Mock Compile-Full-Config {}
        function Validate-Full-Config {}
        Mock Validate-Full-Config {}

        function New-BlockFactory {}
        Mock New-BlockFactory {
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
            $BlockFactory
        }
        function New-LogFactory {}
        Mock New-LogFactory {
            $LogFactory = [PSCustomObject]@{}
            $LogFactory | Add-Member -Name 'InitStatus' -MemberType ScriptMethod -Value {}
            $LogFactory | Add-Member -Name 'DumpStatus' -MemberType ScriptMethod -Value {}
            $LogFactory
        }
        function New-LogObject {}
        Mock New-LogObject {}
        function Process-Local-Block {}
        Mock Process-Local-Block {}

    }


    Context 'Invalid parameters (Non-Terminating)' {

        $eaPreference = 'Continue'

        It 'errors when config is null' {
            $invalidConfig = $null

            $err = Log-Rotate -Config $invalidConfig -ErrorAction $eaPreference 2>&1
            $err | ? { $_ -is [System.Management.Automation.ErrorRecord] } | % { $_.Exception.Message } | Should -Contain "No config file(s) specified."
        }

        It 'errors when config is an non-existing file' {
            $invalidConfig = 'foo'
            Mock Test-Path { $false }

            $err = Log-Rotate -Config $invalidConfig -ErrorAction $eaPreference 2>&1
            $err | ? { $_ -is [System.Management.Automation.ErrorRecord] } | % { $_.Exception.Message } | Should -Contain "Invalid config path specified: $invalidConfig"
        }

        It 'errors when configAsString is null' {
            $invalidConfigAsString = $null

            $err = Log-Rotate -ConfigAsString $invalidConfigAsString -ErrorAction $eaPreference 2>&1
            $err | ? { $_ -is [System.Management.Automation.ErrorRecord] } | % { $_.Exception.Message } | Should -Contain "No config file(s) specified."
        }
    }

    Context 'Invalid parameters (Terminating)' {

        $eaPreference = 'Stop'

        It 'errors when config is null' {
            $invalidConfig = $null

            { Log-Rotate -Config $invalidConfig -ErrorAction $eaPreference 2>$null } | Should -Throw "No config file(s) specified."
        }

        It 'errors when config is an non-existing file' {
            $invalidConfig = 'foo'
            Mock Test-Path { $false }
6
            { Log-Rotate -Config $invalidConfig -ErrorAction $eaPreference  2>$null } | Should -Throw "Invalid config path specified: $invalidConfig"
        }

        It 'errors when configAsString is null' {
            $invalidConfigAsString = $null

            { Log-Rotate -ConfigAsString $invalidConfigAsString -ErrorAction $eaPreference 2>$null } | Should -Throw "No config file(s) specified."
        }
    }

    Context 'Functionality' {

        $eaPreference =  'Stop'

        It 'shows the version' {
            $version = Log-Rotate -Version -ErrorAction $eaPreference

            $version | Should -Match '\d+\.\d+\.\d+$'
        }

        It 'shows the help' {
            $help = Log-Rotate -Help -ErrorAction $eaPreference

            $help | Should -Not -Be $null
        }

        It 'compiles configuration from one config file' {
            . $initScriptBlock
            Mock Compile-Full-Config {}

            Log-Rotate -config $configFile -ErrorAction $eaPreference

            Assert-MockCalled Compile-Full-Config -Times 1
        }

        It 'compiles configuration from multiple config files' {
            . $initScriptBlock
            Mock Test-Path -ParameterFilter { $Path -eq 'foo' -and $PathType } { $false }
            Mock Compile-Full-Config {}

            Log-Rotate -config $configFile -ErrorAction $eaPreference

            Assert-MockCalled Compile-Full-Config -Times 1
        }

        It 'validates configuration' {
            . $initScriptBlock
            Mock Validate-Full-Config {}

            Log-Rotate -config $configFile -ErrorAction $eaPreference

            Assert-MockCalled Validate-Full-Config -Times 1
        }

        It 'instantiates singleton BlockFactory' {
            . $initScriptBlock
            Mock New-BlockFactory {
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
                $BlockFactory
            }

            Log-Rotate -config $configFile -ErrorAction $eaPreference

            Assert-MockCalled New-BlockFactory -Times 1
        }

        It 'instantiates singleton LogFactory' {
            . $initScriptBlock

            Log-Rotate -config $configFile -ErrorAction $eaPreference

            Assert-MockCalled New-LogFactory -Times 1
        }

        It 'instantiates singleton LogObject' {
            . $initScriptBlock

            Log-Rotate -config $configFile -ErrorAction $eaPreference

            Assert-MockCalled New-LogObject -Times 1
        }

        It 'creates block objects from configuration' {
            . $initScriptBlock
            Mock New-BlockFactory {
                $BlockFactory = [PSCustomObject]@{}
                $BlockFactory | Add-Member -Name 'Create' -MemberType ScriptMethod -Value {
                    'create'
                }
                $BlockFactory | Add-Member -Name 'GetAll' -MemberType ScriptMethod -Value {
                    @{
                        '/path/to/foo/bar/' = @{
                            'LogFiles' = @()
                            'Options' = @()
                        }
                    }
                }
                $BlockFactory
            }

            $result = Log-Rotate -config $configFile -ErrorAction $eaPreference

            $result | Should -Be 'create'
        }

        It 'initializes the rotation state file' {
            . $initScriptBlock
            Mock New-LogFactory {
                $LogFactory = [PSCustomObject]@{}
                $LogFactory | Add-Member -Name 'InitStatus' -MemberType ScriptMethod -Value {
                    'initstatus'
                }
                $LogFactory | Add-Member -Name 'DumpStatus' -MemberType ScriptMethod -Value {}
                $LogFactory
            }

            $result = Log-Rotate -config $configFile -ErrorAction $eaPreference

            $result | Should -Be 'initstatus'
        }

        It 'processes a block configuration' {
            . $initScriptBlock

            Log-Rotate -config $configFile -ErrorAction $eaPreference

            Assert-MockCalled Process-Local-Block -Times 1
        }

        It 'dumps the rotation state file' {
            . $initScriptBlock

            Mock New-LogFactory {
                $LogFactory = [PSCustomObject]@{}
                $LogFactory | Add-Member -Name 'InitStatus' -MemberType ScriptMethod -Value {}
                $LogFactory | Add-Member -Name 'DumpStatus' -MemberType ScriptMethod -Value {
                    'dumpstatus'
                }
                $LogFactory
            }

            $result = Log-Rotate -config $configFile -ErrorAction $eaPreference

            $result | Should -Be 'dumpstatus'
        }
    }
}
