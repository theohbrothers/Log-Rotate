function New-BlockFactory {
    #######################
    #  BlockFactory Class #
    #######################
    # BlockFactory is a stateful factory that constructs Block Objects, a Configuration. It keeps a list of Blocks.
    $BlockFactory = [PSCustomObject]@{
        'Constants' = [scriptblock]{
            # Constants
            $g_globaloptions_allowed_str = 'compress,compresscmd,uncompresscmd,compressext,compressoptions,uncompressoptions,copy,copytruncate,create,daily,dateext,dateformat,delaycompress,extension,ifempty,mail,mailfirst,maillast,maxage,minsize,missingok,monthly,nocompress,nocopy,nocopytruncate,nocreate,nodelaycompress,nodateext,nomail,nomissing,noolddir,nosharedscripts,noshred,notifempty,olddir,rotate,size,sharedscripts,shred,shredcycle,start,tabooext,weekly,yearly'
            $g_options_not_singleline_str = 'postrotate,prerotate,firstaction,lastaction,preremove';
            $g_options_not_switches_str = 'compresscmd,uncompresscmd,compressext,compressoptions,uncompressoptions,create,dateformat,extension,include,mail,maxage,minsize,olddir,postrotate,prerotate,firstaction,lastaction,preremove,rotate,size,shredcycle,start,tabooext'

            # Constants as arrays
            [string[]]$g_globaloptions_allowed = $g_globaloptions_allowed_str.Split(',')
            [string[]]$g_options_not_singleline = $g_options_not_singleline_str.Split(',');
            [string[]]$g_localoptions_allowed = $g_globaloptions_allowed + $g_options_not_singleline
            [string[]]$g_options_not_switches = $g_options_not_switches_str.Split(',')

            # Define our config-capturing regexes
            [Regex]$g_localconfigs_regex = '([^\n]*)({(?:(?:(firstaction|lastaction|prerotate|postrotate|preremove)(?:\s|.)*?endscript)|[^}])*})'
            [Regex]$g_globaloptions_allowed_regex = "(?:^|\n)[^\S\n]*\b($( ($g_globaloptions_allowed -join '|') ))\b(.*)"
            [Regex]$g_localoptions_allowed_regex = "\n[^\S\n]*(?:\b($( ($g_globaloptions_allowed -join '|') ))\b(.*)|\b(postrotate|prerotate|firstaction|lastaction|preremove)[^\n]*\n((?:.|\s)*?)\n.*\b(endscript)\b)"
            [hashtable]$g_no_yes = @{
                'nocompress' = 'compress'
                'nocopy' = 'copy'
                'nocopytruncate' = 'copytruncate'
                'nocreate' = 'create'
                'nodelaycompress' = 'delaycompress'
                'nodateext' = 'dateext'
                'nomail' = 'mail'
                'nomissingok' = 'missingok'
                'notifempty' = 'ifempty'
                'noolddir' = 'olddir'
                'nosharedscripts' = 'sharedscripts'
                'noshred' = 'shred'
            }
            #[Regex]$globalconfig_regex = '<?!#(' + ($g_globaloptions_allowed -join '|') + ')'
        }
        'GlobalOptions' = @{
            'compresscmd' = "C:\Program Files\7-Zip\7z.exe"
            'uncompresscmd' = "C:\Program Files\7-Zip\7z.exe"
            'compressext' = '.7z'
            'compressoptions' = 'a -t7z'
            'uncompressoptions' = 'x -t7z'
            'size' = ''
            'dateformat' = '-%Y%m%d'
            'nomissingok' = $true
            'rotate' = 4
            'start' = 1
            'tabooext' = '.rpmorig, .rpmsave, .swp, .rpmnew, ~, .cfsaved, .rhn-cfg-tmp-*.'

            'force' = $force
        }
        'Blocks' = [ordered]@{}
        'UniqueLogFileNames' = New-Object System.Collections.ArrayList
        'PrivateMethods' = [scriptblock]{
            function Get-Options {
                param (
                    [string]$configString,
                    [hashtable]$options_found,
                    [string[]]$options_allowed,
                    [Regex]$options_allowed_regex,
                    [string[]]$options_not_switches
                )

                $matches = $options_allowed_regex.Matches($configString)
                if ($matches.success) {
                    $matches | ForEach-Object {
                        # Get key and value
                        $match = $_
                        $key = if ($match.Groups[1].Value) { $match.Groups[1].Value } else { $match.Groups[3].Value }
                        $value = if ($match.Groups[2].Value) { $match.Groups[2].Value } else { $match.Groups[4].Value }

                        #Write-Verbose "`nLine: $line"
                        #Write-Verbose "key: $key"
                        #Write-Verbose "value: $value"
                        #Write-Verbose "Contains: $($options_allowed.Contains($key))"

                        # Store this option to hashtable. If there are duplicate options, later override earlier ones.
                        if ($key) {
                            if ($options_allowed.Contains($key)) {
                                $options_found[$key] = if ($options_not_switches.Contains($key)) {
                                                            # Don't trim if it's an option with a multiline value
                                                            if (!$g_options_not_singleline.Contains($key)) {
                                                                $value.Trim()
                                                            }else {
                                                                $value
                                                            }
                                                        } else { $true }
                            }
                        }
                    }
                }
                #$options_found
            }

            function Override-Options {
                param (
                    [hashtable]$child,
                    [hashtable]$parent
                )
                # Override my parent options with my options
                $my_options = $parent.Clone()
                $child.GetEnumerator() | ForEach-Object {
                    $key = $_.Name
                    $value = $_.Value
                    $my_options[$key] = $value
                }

                # When I said yes, and I didn't say no, but my parent said no, I will still go ahead.
                $g_no_yes.GetEnumerator() | ForEach-Object {
                    $no = $_.Name
                    $yes = $_.Value

                    if ( $child.ContainsKey($yes) -and (!$child.ContainsKey($no)) -and $parent.ContainsKey($no) ) {
                        $my_options.Remove($no)
                    }
                }
                $my_options
            }

            # Returns an array of log files, that match a given blockpath pattern but whose fullpath is not already present in a unique store
            function Get-Block-Logs {
                param ([object]$blockObject)

                $blockpath = $blockObject['Path']
                $opt_tabooext = $blockObject['Options']['tabooext']
                $opt_missingok = if ($blockObject['Options']['notmissingok']) { $false } else { $blockObject['Options']['missingok'] }

                # Split the blockpath pattern by spaces, to get either 1) log paths or 2) wildcarded-paths
                $logpaths = [System.Collections.Arraylist]@()
                $matches = [Regex]::Matches($blockpath, '"([^"]+)"|([^\s]+)')
                if ($matches.success) {
                    $matches | ForEach-Object {
                        $path = if ($_.Groups[1].Value.Trim()) {
                                    $_.Groups[1].Value
                                }else {
                                    $_.Groups[2].Value
                                }
                        if ($path) {
                            $logpaths.Add($path) | Out-Null
                        }
                    }
                }

                # Get all the log files matching path patterns defined in the Config.
                $logfiles = New-Object System.Collections.Arraylist
                foreach ($logpath in $logpaths) {
                    # Test if the path (without any wildcards) exists
                    if ($logpath -match '\*') {

                        # It's a wildcarded path.
                        Write-Verbose "Considering wildcarded path $logpath"

                        if (Test-Path -Path $logpath) {
                            # Add all files that match the wildcard path
                            $items = Get-ChildItem $logpath -File | Where-Object { (likeIn $_.Name $opt_tabooext.Split(',').Trim()) -eq $false }
                            $items | ForEach-Object {
                                $logfiles.Add($_) | Out-Null
                            }
                        }else {
                            if (!$opt_missingok) {
                                Write-Verbose "Excluding wildcarded path $logpath for rotation, because it doesn't exist!"
                            }
                        }
                    }else {
                        # It's a non-wildcarded path. Reject if it's a folder.

                        if (Test-Path -LiteralPath $logpath) {
                            $item = Get-Item -Path $logpath
                            if ($item.PSIsContainer) {
                                # It's a directory. Ignore it.
                                if (!$opt_missingok) {
                                    Write-Verbose "Excluding path $logpath for rotation, because it is a directory. Directories cannot be rotated. If rotating all the files in the directory, append a wildcard to the end of the path."
                                }
                            }else {
                                # It's a file. Add
                                $logfiles.Add($item) | Out-Null
                            }
                        }else {
                            if (!$opt_missingok) {
                                Write-Verbose "Excluding log $logpath for rotation, because it doesn't exist or does not point to file!"
                            }
                        }
                    }
                }

                # Add unique log files to our list. If a logs already added, it must be a duplicate so we ignore it.
                if ($logfiles.Count) {
                    $logfileCount = $logfiles.Count - 1
                    foreach ($i in (0..$logfileCount)) {
                        $logfile = $logfiles[$i]
                        if ($logfile.FullName -in $this.UniqueLogFileNames) {
                            Write-Verbose "CONFIG: WARNING - Duplicate Log included: $($logfile.FullName) (matched in block pattern: $blockpath). Skipping rotation for this entry."
                            $logfiles.Remove($logfile)
                        }else {
                            $this.UniqueLogFileNames.Add($logfile.FullName) | Out-Null
                        }
                    }
                }

                $logfiles
            }

        }
    }
    $BlockFactory | Add-Member -Name 'Create' -MemberType ScriptMethod -Value {
        param ([string]$FullConfig)

        # Unpack my properties
        . $this.Constants

        # Unpack my methods
        . $this.PrivateMethods

        # Parse Full Config for global options as hashtable
        $globalconfig = $g_localconfigs_regex.Replace($FullConfig, '')
        Get-Options $globalconfig $this.GlobalOptions $g_globaloptions_allowed $g_globaloptions_allowed_regex $g_options_not_switches

        # Parse Full Config for all found local block(s) path pattern, options, and matching log files, storing them as hashtable. Override the global options.
        # TODO: Regex for localconfigs to match paths on multiple lines before { }
        $matches = $g_localconfigs_regex.Matches($FullConfig)
        if ($matches.success) {
            foreach ($localconfig in $matches) {
                # NOTE: NOT USED ANYMORE: A block pattern should delimit multiple paths with a single space
                #$my_path_pattern = ($localconfig.Groups[1].Value -Split ' ' | Where-Object { $_.Trim() }).Trim() -join ' '
                # Just get the raw path pattern
                $my_path_pattern = $localconfig.Groups[1].Value.Trim()
                if ($my_path_pattern -in $this.Blocks.Keys) {
                    Write-Verbose "CONFIG: WARNING - Duplicate path pattern $my_path_pattern . Only the latest entry will be used."
                }
                # Any duplicate block path pattern overrides the previous
                $this.Blocks[$my_path_pattern] = @{
                    'Path' = $my_path_pattern
                    'Options' = @{}
                    'LocalOptions' = @{}
                    'LogFiles' = ''
                }
                try {
                    Get-Options $localconfig.Groups[2].Value $this.Blocks[$my_path_pattern]['LocalOptions'] $g_localoptions_allowed $g_localoptions_allowed_regex $g_options_not_switches
                    $this.Blocks[$my_path_pattern]['Options'] = Override-Options $this.Blocks[$my_path_pattern]['LocalOptions'] $this.GlobalOptions
                    $this.Blocks[$my_path_pattern]['LogFiles'] = Get-Block-Logs $this.Blocks[$my_path_pattern] $this.UniqueLogFileNames
                } catch {
                    throw
                }
            }
        }else {
            Write-Verbose "CONFIG: WARNING - No configuration blocks were found."
        }
    }
    $BlockFactory | Add-Member -Name 'GetAll' -MemberType ScriptMethod -Value {
        $this.Blocks
    }

    $BlockFactory
}
