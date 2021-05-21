function Process-Local-Block  {
    # Validates options for the block, and instantiates any Log Objects.
    [CmdletBinding()]
    param (
        # The Block object
        [Parameter(Mandatory=$True)]
        [object]$block,

        # Block Options
        [switch]$compress,
        [string]$compresscmd,
        [string]$uncompresscmd,
        [string]$compressext,
        [string]$compressoptions,
        [string]$uncompressoptions,
        [switch]$copy,
        [switch]$copytruncate,
        [string]$create,
        [switch]$daily,
        [switch]$delaycompress,
        [switch]$dateext,
        [string]$dateformat,
        [string]$extension,
        [switch]$ifempty,
        [string]$include,
        [string]$mail ,
        [switch]$mailfirst ,
        [switch]$maillast ,
        [string]$maxage ,
        [string]$minsize ,
        [switch]$missingok ,
        [switch]$monthly,
        [switch]$nocompress,
        [switch]$nocopy,
        [switch]$nocopytruncate,
        [switch]$nocreate,
        [switch]$nodelaycompress,
        [switch]$nodateext,
        [switch]$nomail,
        [switch]$nomissingok,
        [switch]$noolddir,
        [switch]$nosharedscripts,
        [switch]$noshred,
        [switch]$notifempty,
        [string]$olddir,
        [string]$postrotate,
        [string]$prerotate,
        [string]$firstaction,
        [string]$lastaction,
        [string]$preremove,
        [int]$rotate,
        [string]$size,
        [switch]$sharedscripts,
        [switch]$shred,
        [switch]$shredcycle,
        [int]$start,
        [string]$tabooext,
        [switch]$weekly,
        [switch]$yearly,

        [switch]$force
    )

    # Validates options for a block
    begin
    {
        # Unpack this block's properties
        $blockpath = $block.Path
        $logfiles = $block.Logfiles

        # $PSBoundParameters automatic variable is a hashtable containing all bound parameters (keys) and their arguments(values). These are our options.
        $options = $PSBoundParameters

        # Override options where overrides exist in this local block

        # Don't do any of the following if we defined so
        $options['compress'] = if ($nocompress) { $false } else { $compress }
        $options['copy'] =  & {
                                if ($nocopy) {
                                    return $false
                                }
                                if ($copy) {
                                    return $true
                                }
                                if ($nocopytruncate) {
                                    return $false
                                }
                                if ($copytruncate) {
                                    return $true
                                }
                                $copy
                            }
        $options['copytruncate'] = if ($nocopytruncate) { $false } else { $copytruncate }
        $options['create'] = if ($nocreate) { '' } else { $create }
        $options['delaycompress'] = if ($nodelaycompress) { $false } else { $delaycompress }
        $options['dateext'] = if ($nodateext) { $false } else { $dateext }
        $options['mail'] = if ($nomail) { $false } else { $mail }
        $options['missingok'] = if ($nomissingok) { $false } else { $missingok }
        $options['ifempty'] = if ($notifempty) { $false } else { $ifempty }
        $options['olddir'] = if ($noolddir) { '' } else { $olddir }
        $options['sharedscripts'] = if ($nosharedscripts) { $false } else { $sharedscripts }
        $options['shred'] = if ($noshred) { $false } else { $shred }

        # Compress extension
        $options['compressext']  =  if ($options['compress']) {
                                        if ($compressext) {
                                            # Use the specified compression file extension
                                            $compressext
                                        }else {
                                            # Try and guess the compression file extension to use
                                            if ($compresscmd -match '7za?') {
                                                '.7z'
                                            }elseif ($compresscmd -match 'gzip') {
                                                '.gz'
                                            }
                                        }
                                    }else {
                                        ''
                                    }
       # Validate that the compress command exists
        if ($compress -and !$nocompress) {
            try {
                Get-Command $compresscmd -ErrorAction Stop | Out-Null
            }catch {
                Write-Error "Skipping log pattern $blockpath because of an invalid compress command '$compresscmd'. $(Get-Exception-Message $_)" -ErrorAction Stop
            }
        }
        # Validate dateformat if using dateext
        # Exit here, if invalid!
        if ($dateext) {
            if ($dateformat.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ne -1)  {
                Write-Error "Skipping log pattern $blockpath because there are invalid characters in option 'dateext'." -ErrorAction Stop
            }
        }

        # Validate / redefine size
        # Exit here, if invalid!
        if ($size) {
            try {
                $_size_bytes = Get-Size-Bytes $size
                if ($_size_bytes) {
                    $options['size'] =  $_size_bytes
                } else {
                    Write-Error "Skipping log pattern $blockpath because size cannot be 0." -ErrorAction Stop
                }
            }catch {
                Write-Error "Skipping log pattern $blockpath because of an invalid 'size' option. $(Get-Exception-Message $_)" -ErrorAction Stop
            }
        }

        if ($minsize) {
            try {
                $_minsize_bytes = Get-Size-Bytes $minsize
                if ($_minsize_bytes) {
                    $options['minsize'] =  $_minsize_bytes
                }else {
                    Write-Error "Skipping log pattern $blockpath because minsize cannot be 0." -ErrorAction Stop
                }
            }catch {
                #throw "Skipping log pattern $blockpath because of an invalid 'minsize' option. $(Get-Exception-Message $_)"
                Write-Error "Skipping log pattern $blockpath because of an invalid 'minsize' option. $(Get-Exception-Message $_)" -ErrorAction Stop
            }
        }
    }

    # Constructs Log Objects for log files determined to be rotated. Rotates those logs.
    process
    {
        #try {
            # Status Messages
            if ($force) {
                $_force_msg = "forced from command line"
            }
            Write-Verbose "Rotating pattern: $blockpath  $(Get-Size-Bytes $size) bytes  $_force_msg ($rotate rotations)"
            $_msg = ''
            if ($olddir) {
                $_msg += "olddir is $olddir"
            }
            if (!$ifempty) {
                if ($_msg) { $_msg += ', ' }
                $_msg += "empty log files are not rotated"
            }

            if ($_msg) { $_msg += ', ' }
            if ($mail -and ($mailfirst -or $maillast)) {
                $_msg += "old logs are mailed to $mail"
            }else {
                $_msg += "old logs are removed."
            }
            Write-Verbose $_msg

            if ($logfiles.Count) {
                # Get an array of Log Objects of to-be-rotated log files.
                $_logsToRotate = New-Object System.Collections.ArrayList
                foreach ($logfile in $logfiles) {
                    Write-Verbose "Considering log $($logfile.FullName)"
                    try {
                        $_logObject = $LogFactory.Create($logfile, $options)
                        if ($_logObject) {
                            $_logsToRotate.Add($_logObject) | Out-Null
                            Write-Verbose "    log needs rotating"
                        }else {
                            Write-Verbose "    log does not need rotating."
                        }
                    }catch {
                        Write-Error "Skipping over processing log $($logfile.FullName) because $(Get-Exception-Message $_)" -ErrorAction Continue
                    }
                }

                # These Log Objects should be rotated. Rotate them.
                if ($_logsToRotate.Count -gt 0) {
                    # Run any firstaction/endscript
                    if ($firstaction) {
                        try {
                            # Script output will go down the pipeline
                            Write-Verbose "Running firstaction script"
                            Start-Script $firstaction $blockpath -ErrorAction $CallerEA
                        }catch {
                            Write-Error "Failed to run firstaction script for $blockpath because $(Get-Exception-Message $_)" -ErrorAction $CallerEA
                        }
                    }

                    # For sharedscripts, prerotate and postrotate scripts are run once, immediately before and after all of this block's logs are rotated.
                    # For nosharedscripts, prerotate and postrotate scripts run for each log, immediately before and after it is rotated.
                    if ($options['sharedscripts']) {
                        # Do PrePrerotate
                        $_logsToRotate | ForEach-Object {
                            try {
                                # Script output will go down the pipeline
                                $log = $_
                                $log.PrePrerotate()
                            }catch {
                                Write-Error "Failed to rotate log $($log['logfile'].FullName). $(Get-Exception-Message $_)" -ErrorAction Continue
                            }
                        }

                        # Run any prerotate/endscript, only if using sharedscripts
                        if ( $prerotate -and ($false -notin $_logsToRotate.status.preprerotate) ) {
                            try {
                                # Script output will go down the pipeline
                                Write-Verbose "Running shared prerotate script"
                                Start-Script $prerotate $blockpath -ErrorAction $CallerEA
                            }catch {
                                Write-Error "Failed to run shared prerotate script for $blockpath. $(Get-Exception-Message $_)" -ErrorAction Stop
                            }
                        }

                        # It's time to rotate each of these Log Objects
                        $_logsToRotate | Where-Object { $_.status.preprerotate -eq $true } | ForEach-Object {
                            try {
                                # Script output will go down the pipeline
                                $log = $_
                                $log.RotateMainOnly()
                            }catch {
                                Write-Error "Failed to rotate log $($log['logfile'].FullName). $(Get-Exception-Message $_)" -ErrorAction Continue
                            }
                        }

                        # Run any postrotate/endscript, only if using sharedscripts
                        if ( $postrotate -and ($false -notin $_logsToRotate.status.rotate) ) {
                            try {
                                Write-Verbose "Running shared postrotate script"
                                # Script output will go down the pipeline
                                Start-Script $postrotate $blockpath -ErrorAction $CallerEA
                            }catch {
                                Write-Error "Failed to run shared postrotate script for $blockpath. $(Get-Exception-Message $_)" -ErrorAction Stop
                            }
                        }

                        # Do PostPostRotate
                        $_logsToRotate | Where-Object { $_.status.preprerotate -eq $true -and $_.status.rotate -eq $true } | ForEach-Object {
                            try {
                                # Script output will go down the pipeline
                                $log = $_
                                $log.PostPostRotate()
                            }catch {
                                Write-Error "Failed to rotate log $($log['logfile'].FullName). $(Get-Exception-Message $_)" -ErrorAction Continue
                            }
                        }
                    }else {
                        $_logsToRotate | ForEach-Object {
                            # For each log to rotate: move step-by-step but dont continue if a step is unsuccessful.
                            try {
                                # Script output will go down the pipeline
                                $_.PrePrerotate()
                                if ( $_.status.preprerotate -and $prerotate ) { $_.Prerotate() }
                                if ( ! $prerotate -or ( $prerotate -and $_.status.prerotate ) ) { $_.RotateMainOnly() }
                                if ( $_.status.rotate -and $postrotate ) { $_.Postrotate() }
                                if ( ! $postrotate -or ( $postrotate -and $_.status.postrotate ) ) { $_.PostPostRotate() }
                            }catch {
                                Write-Error $(Get-Exception-Message $_) -ErrorAction $CallerEA
                            }
                        }
                    }

                    # Run any lastaction/endscript
                    if ($lastaction) {
                        try {
                            # Script output will go down the pipeline
                            Write-Verbose "Running lastaction script" -ErrorAction Stop
                            Start-Script $lastaction $blockpath -ErrorAction $CallerEA
                        }catch {
                            Write-Error "Failed to run lastaction script for $blockpath. $(Get-Exception-Message $_)" -ErrorAction Stop
                        }
                    }
                }else {
                    if ($DebugFlag) {
                        Write-Verbose "Not running first action script, since no logs will be rotated"
                        Write-Verbose "Not running prerotate script, since no logs will be rotated"
                        Write-Verbose "Not running postrotate script, since no logs will be rotated"
                        Write-Verbose "Not running last action script, since no logs will be rotated"
                    }
                }
            }else {
                Write-Verbose "Did not find any logs for path $logpath"
            }
        #}catch {
        #    Write-Error $_.Exception.Message -ErrorAction Stop
        #}

    }
    end {
    }
}
