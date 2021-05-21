# Log-Rotate Cmdlet
function Log-Rotate {
    <#
    .SYNOPSIS
    A replica of the logrotate utility, except this also runs on Windows systems.

    .DESCRIPTION
    The functionality of Log-Rotate was ported from the original logrotate.
    It is made to work in the exact way logrotate would work: Same rotation logic, same outputs, same configurations.
    Best of all, it works on one more platform: Windows.

    .PARAMETER Config
    The path to the Log-Rotate config file, or the path to a directory containing config files. If a directory is given, all files will be read as config files.
    Any number of config file paths can be given.
    Later config files will override earlier ones.
    The best method is to use a single config file that includes other config files by using the 'include' directive.

    .PARAMETER ConfigAsString
    The configuration as a string, accepting input from the pipeline. Especially useful when you don't want to use a separate config file.

    .PARAMETER Debug
    In debug mode, no logs are rotated. Use this to validate your configs or observe rotation logic.

    .PARAMETER Force
    Forces Log-Rotate to perform a rotation for all Logs, even when Log-Rotate deems particular Log(s) to not require rotation.

    .PARAMETER Help
    Prints Help information.

    .PARAMETER Mail
    Tells logrotate which command to use when mailing logs.

    .PARAMETER State
    The path to a Log-Rotate state file to use for previously rotated Logs. May be absolute or relative.
    If no state file is provided, by default the location of the state file (named 'Log-Rotate.state') will be in the calling script's directory. If there is no calling script, the location of the state file will be in the current working directory.
    If a relative path is provided, the state file path will be resolved to the current working directory.
    If a tilde ('~') is used at the beginning of the path, the state file path will be resolved to the user's home directory.

    .PARAMETER Usage
    Prints Usage information

    .EXAMPLE
    Log-Rotate -ConfigAsString $configAsString -State $state -Verbose

    .EXAMPLE
    Log-Rotate -Config "/etc/Log-Rotate.conf" -State "/var/lib/Log-Rotate/Log-Rotate.status" -Verbose

    .EXAMPLE
    Log-Rotate -Config "/etc/configs/" -Verbose

    .LINK
    https://github.com/leojonathanoh/Log-Rotate

    .NOTES
    *logrotate manual: https://linux.die.net/man/8/logrotate

    The command line is identical to the actual logrotate utility, if parameter aliases are used. If using full parameters, only optional (-mail, -state) and miscellaneous (-usage, -help) parameters use one instead of two dashes. (i.e. -mail instead of --mail)
    For help on command line options, use:
        Get-Help Log-Rotate -detailed

    Configuration file(s) should follow the same format and options used by the actual logrotate utility.
    See the logrotate manual* for configuration options.

    Because logrotate is constantly being updated, the present utility may not be up to par with it. But it won't be too hard or too long for new features to be integrated.
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [string]$ConfigAsString
    ,
        [alias("c")]
        [string[]]$Config
    ,
        [alias("d")]
        [switch]$WhatIf
    ,
        [alias("f")]
        [switch]$Force
    ,
        [alias("h")]
        [switch]$Help
    ,
        [alias("m")]
        [string]$Mail
    ,
        [alias("s")]
        [string]$State
    ,
        [alias("u")]
        [switch]$Usage
        ,
        [alias("v")]
        [switch]$Version
    )

    if ($WhatIf) {
        Write-Warning "We are in Debug mode. No logs will be rotated."
        $VerbosePreference = 'Continue'
    }
    if ($Force) {
        Write-Warning "We are in Forced-Rotation mode."
    }

    # Debug bitwise flag (for developers)
    # Enter the sum of all the options you want.
    # All values above 1 implies 1.
    # 0 - Off
    # 1 - On, script does not change files. Calling Log-Rotate with -Debug will switch this to 1.
    # 2 - Output Stacktrace in error messages
    # 4 - On, verbose mode. Implies (1). This is NOT related to calling Log-Rotate with -Verbose, but strictly for debugging messages.
    $WhatIf = 0
    if ($WhatIf) {
        Write-Warning "Developer's debug flag is on."
    }

    # Use Caller Error action if specified
    $CallerEA = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'

    # Always use verbose mode?
    #$VerbosePreference = 'Continue'

    # Global scope debug preference
    $DebugPreferenceOld = $DebugPreference
    if ($DebugPreference -eq 'Inquire') {
        # If we're using the -debug flag, always use -verbose mode.
        $DebugPreference = 'Continue'
        # Preserve our set debug flag for testing
        $WhatIf = if ($WhatIf) { $WhatIf } else { 1 }
    }else {
         # If we're not using the -debug flag, debug should stay silent instead of prompting.
        $DebugPreference = 'SilentlyContinue'
    }

    # PS Defaults
    $PSDefaultParameterValues['*-Content:Force'] = $true
    $PSDefaultParameterValues['*-Item:Force'] = $true
    $PSDefaultParameterValues['Get-ChildItem:Force'] = $true
    $PSDefaultParameterValues['Out-File:Force'] = $true
    $PSDefaultParameterValues['Invoke-Command:ErrorAction'] = 'Stop'

    # Prints miscellaneous information and exits
    $LogRotateVersion = '1.2.2'
    if ($Version) {
        Write-Output "Log-Rotate $LogRotateVersion"
        return
    }
    if ($Help) {
        Write-Output (Get-Help Log-Rotate -Full)
        return
    }
    if ($Usage) {
        Write-Output (Get-Help Log-Rotate)
        return
    }

    try {
        Write-Verbose "------------------------------ Log-Rotate --------------------------------------"
        # Will always reflect the calling script's path, even when used as a Module
        if ($MyInvocation.PSCommandPath) {
            Write-Verbose "Script root: $( Split-Path -parent $MyInvocation.PSCommandPath )"
        }
        #Write-Verbose "Current working directory: $( Convert-Path . )"
        Write-Verbose "Current working directory: $( $(Get-Location).Path )"


        # Get the configuration as a string
        if ($ConfigAsString) {
            # Pipelined string. Keep going
            $MultipleConfig = $ConfigAsString
        }else {
            # No pipeline string. From this point on $Config has to be an array of: a path to a config file, or directory containing config files.
            if (!$Config) {
                Write-Error "No config file(s) specified." -ErrorAction Stop
            }
            try {
                $MultipleConfig = ''
                $Config | ForEach-Object {
                    # Path has to be valid
                    if (Test-Path $_) {

                        $item = Get-Item $_
                        if ($item.PSIsContainer) {
                            # It's a directory. Consider all child files as config files.
                            Get-ChildItem $item.FullName -File | ForEach-Object {
                                Write-Verbose "Config file found: $($_.FullName)"
                                $MultipleConfig += "`n" + (Get-Content $_.FullName -Raw -ErrorAction Stop)
                            }
                        }else {
                            # It's a file.
                            Write-Verbose "Config file found: $($item.FullName)"
                            $MultipleConfig += "`n" + (Get-Content $item.FullName -Raw -ErrorAction Stop)
                        }

                    }else {
                        throw "Invalid config path specified: $_"
                    }
                }
            }catch {
                Write-Error "Unable to retrieve content of config $Config" -ErrorAction Continue
                throw
            }
        }

        # Instantiate our BlockFactory and LogFactory
        #$BlockFactory = $BlockFactory.psobject.copy()
        #$LogFactory = $LogFactory.psobject.copy()

        # Compile our Full Config
        $FullConfig = Compile-Full-Config $MultipleConfig

        # Validate our Full Config
        Validate-Full-Config $FullConfig

        # Instantiate Singletons
        $BlockFactory = New-BlockFactory
        $LogFactory = New-LogFactory
        $LogObject = New-LogObject

        # Create Blocks from our Full Config
        $BlockFactory.Create($FullConfig)

        # Initialize our Rotation Status
        $LogFactory.InitStatus($State)

        $count = 0
        $BlockFactory.GetAll().GetEnumerator() | ForEach-Object {
            $count += $_.Value.LogFiles.Count
        }
        Write-Verbose "Handling $count logs"
        # Run Log-Rotate for each defined block
        $blocks = $BlockFactory.GetAll()
        $blocks.GetEnumerator() | ForEach-Object {
            # This block object.
            $block = $_.Value
            $blockoptions = $block.Options

            # Rotate each log of this block
            Process-Local-Block -block $block @blockoptions
        }

        # Finish up with dumping status
        $LogFactory.DumpStatus()
    }catch {
        Write-Error -ErrorRecord $_ -ErrorAction $CallerEA
    }
}
