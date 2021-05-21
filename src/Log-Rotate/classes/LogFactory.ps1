#######################
#   LogFactory Class   #
#######################
# LogFactory is a stateful factory that constructs Log Objects, and tracks their last rotation status.
$LogFactory = [PSCustomObject]@{
    'LogObjects' = New-Object System.Collections.ArrayList
    'Status' = @{}
    'StatusFile_FullName' = if ( $MyInvocation.PSCommandPath ) {
                                # Use the calling script's directory if so
                                "$( Split-Path $MyInvocation.PSCommandPath -parent )$( [IO.Path]::DirectorySeparatorChar )Log-Rotate.status"
                            }else {
                                # Or fallback on the current working directory
                                Join-Path $(Get-Location) 'Log-Rotate.status'
                            }
}
$LogFactory | Add-Member -Name 'InitStatus' -MemberType ScriptMethod -Value {
    param ([string]$statusfile_path)

    # If no status file is specified, we'll consider it to be in script directory called 'Log-Rotate.status'
    if (!$statusfile_path) {
        $statusfile_path = $this.StatusFile_FullName
    }

    if ($statusfile_path) {
        # Ensure status file path contains valid characters
        try {
            $exists = Test-Path -LiteralPath $statusfile_path -ErrorAction Stop
        }catch {
            # Illegal characters in path
            throw "STATUSFILE: WARNING: Invalid status file $statusfile_path . $( Get-Exception-Message $_ )"
        }

        if ($exists) {
            # Ensure it's not an existing diretory
            $item = Get-Item $statusfile_path -ErrorAction Stop
            if ($item.PSIsContainer) {
                throw "STATUSFILE: WARNING: Invalid status file $statusfile_path . It points to an existing directory $($item.FullName)."
            }

            try {
                # Make it an absolute path, if it is not
                $this.StatusFile_FullName = Convert-Path $statusfile_path

                Write-Verbose "status file: $( $this.StatusFile_FullName )"

                # Read status
                $status = Get-Content $this.StatusFile_FullName -Raw
            }catch {
                throw "STATUSFILE: WARNING: Status file $( $this.StatusFile_FullName ) could not be read. $( Get-Exception-Message $_ )"
            }
        }else {
            # Create a new status file, creating all directories if needed. If a relative path was given, it will be resolved to the current working directory.
            try {

                #[io.file]::OpenWrite($statusfile_path).close()
                $item = New-Item -Path $statusfile_path -ItemType File -Force -ErrorAction Stop
                if ($item) {
                    # Store state file fullname (absolute path).
                    $this.StatusFile_FullName = $item.FullName
                    $this.DumpStatus()
                    Write-Verbose "new status file created: $( $this.StatusFile_FullName )"
                }else {
                    throw
                }

                ## NOTE: Not using this, because debugging should also test the creation of a file.
                # The reason for using the following code is only because the cmdlets such as Convert-Path, Resolve-Path must point to an existing item.
                # If debugging didn't create the file, we would have to manually normalize the status file path (i.e. get it's absolute path).
                <#
                if ($WhatIf) {
                    $is_home = $statusfile_path -match '^~'
                    if ($is_home) {
                        # It's an absolute path
                        $parent = Convert-Path '~'
                        $child = $statusfile_path -replace '^~', ''
                        $this.StatusFile_FullName = Join-Path -Path $parent -ChildPath $child
                    }else {
                        if ( ! [System.IO.Path]::IsPathRooted($statusfile_path) ) {
                            # A relative path was provided.

                            # Can't use Convert-Path / Resolve-Path which must point to an existing item
                            # Build the absolute path to the status file.
                            # E.g. 'D:\mycwd\Log-Rotate.status' -> 'D:\mycwd\Log-Rotate.status'
                            # E.g. 'D:\mycwd\.\Log-Rotate.status' -> 'D:\mycwd\Log-Rotate.status'
                            # E.g. 'D:\mycwd\..\Log-Rotate.status' -> 'D:\Log-Rotate.status'
                            # E.g. 'D:\mycwd\..\test\Log-Rotate.status' -> 'D:\test\Log-Rotate.status'
                            $path = Join-Path -Path $PWD.Path -ChildPath $statusfile_path
                            $this.StatusFile_FullName = [System.IO.Path]::GetFullPath( $path )
                        }else {
                            # An absolute path was provided. Standardize the slashes to platform-specific slashes ([IO.Path]::DirectorySeparatorChar)
                            $this.StatusFile_FullName = [System.IO.Path]::GetFullPath( $statusfile_path )
                        }
                    }
                    Write-Verbose "new status file created: $( $this.StatusFile_FullName )"
                }
                #>
            }catch {
                throw "STATUSFILE: WARNING: Status file $statusfile_path could not be created. $( Get-Exception-Message $_ )"
            }
        }
    }

    # Parse and store previous rotation status
    if ($status) {
        $lines = $status.split("`n")

        # The first line must be a Log-Rotate state file title, if not we might be dealing with another file.
        if ( $lines[0] -notmatch 'Log\-Rotate state' ) {
            throw "Log-Rotate state file $( $this.StatusFile_FullName ) is of the wrong format. Check that you are not overriding another file. If you are not, delete the file and try again."
        }

        $lines.Trim() | Where-Object { $_ } | ForEach-Object {
            $matches = [Regex]::Matches($_, '"([^"]+)" (.+)')
            if ($matches.success) {
                $path = $matches.Groups[1].Value
                $lastRotateDate = $matches.Groups[2].Value
                if (Test-Path $path -PathType Leaf) {
                    try {
                        $lastRotateDatetime = Get-Date -Date $lastRotateDate -Format 's' -ErrorAction SilentlyContinue
                        $this.Status[$path] = $lastRotateDatetime
                    }catch {}
                }
            }
        }
    }

    # Always test for write permissions on the status file
    try {
        '' | Out-File $this.StatusFile_FullName -Append -Force
        if (!$status -and $WhatIf) {
            # We're running Log-Rotate the first time in debug mode.
            Remove-Item $this.StatusFile_FullName
        }
    }catch {
        throw "STATUSFILE: WARNING: Insufficient write permissions for status file $( $this.StatusFile_FullName ). Resolve this error before continuing. Reason: $( Get-Exception-Message $_ )"
    }
}
$LogFactory | Add-Member -Name 'Create' -MemberType ScriptMethod -Value {
    param ([System.IO.FileInfo]$logfile, [hashtable]$options)

    function Get-Status([System.IO.FileInfo]$file) {
        $lastRotationDate = if ($this.Status.ContainsKey($file.FullName)) {
                                $this.Status[$file.FullName]
                            }else {
                                ''
                            }
        [string]$lastRotationDate
    }

    $lastRotationDate = Get-Status $logfile
    $_logObject = $LogObject.New($logfile, $options, $lastRotationDate)
    if ($_logObject)  {
        $this.LogObjects.Add($_logObject) | Out-Null
        return $_logObject
    }
    $null
}
$LogFactory | Add-Member -Name 'GetAll' -MemberType ScriptMethod -Value {
    return $this.LogObjects
}
$LogFactory | Add-Member -Name 'DumpStatus' -MemberType ScriptMethod -Value {

    try {
        if (!$WhatIf) {
            # Update my state with each logs rotation status
            $this.GetAll() | Where-Object { $_.Status['rotation_datetime'] } | ForEach-Object {
                $rotationDateISO = $_.Status['rotation_datetime'].ToString('s')
                $lastRotationDateISO =  if ($this.Status.ContainsKey($_.Logfile.FullName)) {
                                            $this.Status[$_.Logfile.FullName]
                                        } else {
                                            ''
                                        }
                if ( !$lastRotationDateISO -or ($rotationDateISO -gt $lastRotationDateISO) ) {
                    Write-Verbose "Updating status of rotation for log $($_.Logfile.FullName) "
                    $this.Status[$_.Logfile.FullName] = $rotationDateISO
                }else {
                    Write-Verbose "Not updating status of rotation for log $($_.Logfile.FullName) "
                }
            }

            # Dump state file
            Write-Verbose "Writing status file to $($this.StatusFile_FullName)"
            $output = "Log-Rotate state - version $LogRotateVersion"
            $this.Status.Keys | ForEach-Object {
                $output += "`n`"$_`" $($this.Status[$_])"
            }
            $output | Out-File $this.StatusFile_FullName -Encoding utf8
        }else {
            # Dump state file
            Write-Verbose "Writing status file to $($this.StatusFile_FullName)"
        }
    }catch {
        throw "Failed to write state file! Reason: $(Get-Exception-Message $_)"
    }
}
