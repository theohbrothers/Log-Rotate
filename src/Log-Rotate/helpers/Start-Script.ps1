function Start-Script {
    [CmdletBinding()]
    param (
        [AllowNull()]
        [string]$script,
        [string]$file_FullName
    )

    begin {
        # Save the caller's ErrorAction
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
    }

    process {
        try {
            Write-Verbose "Running script with arg $file_FullName : `n$script"
            $OS = $ENV:OS
            if (!$DebugFlag) {
                if ($OS -eq "Windows_NT") {
                    # E.g. & Powershell -Command { echo $Args[0] } -Args @('D:/console.log')

                    # & operator: When we use & $cmd $param, powershell wraps args containing spaces with double-quotes, so we need escape inner double-quotes
                    $cmd =  if ( Get-Command 'powershell' -ErrorAction SilentlyContinue ) {
                                "powershell"
                            }elseif ( Get-Command 'pwsh' -ErrorAction SilentlyContinue ) {
                                "pwsh"
                            }
                    $scriptblock = [scriptblock]::Create($script)
                    #$params = '-Command', $scriptblock, '-Args', @($file_FullName)
                    $output = & $cmd -Command $scriptblock -Args @('logrotate_script', $file_FullName)
                }else {
                    # E.g. sh -c 'echo ${0}' 'D:\console.log'

                    # & operator: When we use & $cmd $param, powershell wraps args containing spaces with double-quotes, so we need escape inner double-quotes
                    $cmd = 'sh'
                    $params = '-c', $script.Replace('"', '\"'), 'logrotate_script', $file_FullName
                    $output = & $cmd $params

                    # TODO: Not using jobs for now, because they are slow.
                    #$script = "sh -c '$script' `$args[0]"
                }

                Write-Verbose "Script output: `n$output"

                # Done. Send output down the pipeline. If not, send the success of the script down the pipeline
                if ( $LASTEXITCODE ) {
                    Write-Verbose "Script exited with exit code: $LASTEXITCODE"
                    throw "Script failed with errors."
                }
                $output

                # TODO: Not using jobs for now, because they are slow.
                <#
                $scriptblock = [Scriptblock]::Create($script)
                $output = & $scriptblock $file_FullName
                $job = Start-Job -ScriptBlock $scriptblock -ArgumentList $file_FullName -ErrorAction Stop
                $output = Receive-Job -Job $job -Wait -ErrorAction Stop
                if ($job.State -eq 'Failed') {
                    throw
                }else {
                    Write-Verbose "Script output: `n$output"
                }
                #>
            }
        }catch {
            throw "Failed to execute script for $file_FullName. `nError: $_ `nScript (possibly with errors): $script"
        }
    }
}
