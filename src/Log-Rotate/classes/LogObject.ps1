#####################
#  LogObject Class #
#####################
# Properties
$LogObject = [PSCustomObject]@{
    'Logfile' = ''
    'Options' = ''
    'Status' = ''
    'Metadata' = ''
    'PrivateMethods'= [scriptblock]{
        ##########################
        # Object Private Methods
        ##########################
        function Rotate-Main {
            try {
                # Rotate main file
                # E.g. D:/console.log -> D:/console.log.1
                if ($copy) {
                    Write-Verbose "Copying $my_fullname to $my_previous_fullname"

                    if (Test-Path $my_previous_fullname) {
                        # File exists.
                        Write-Verbose "Error creating output file $my_previous_fullname`: File exists"
                    }else {
                        if (!$g_debugFlag) {
                            Copy-Item $my_fullname $my_previous_fullname -ErrorAction Stop
                        }
                        if ($copytruncate) {
                            Write-Verbose "Truncating $my_fullname"
                            if (!$g_debugFlag) {
                                Clear-Content $my_fullname
                            }
                        }else {
                            Write-Verbose "Not truncating $my_fullname"
                        }
                        return $true
                    }
                }else {
                    Write-Verbose "Renaming $my_fullname to $my_previous_fullname"
                    if (Test-Path $my_previous_fullname) {
                        # File exists.
                        Write-Verbose "Error creating output file $my_previous_fullname`: File exists"
                    }else {
                        if (!$g_debugFlag) {
                            Move-Item $my_fullname $my_previous_fullname -Force
                        }
                        if ($create) {
                            Write-Verbose "Creating new log file $my_fullname"
                            if (!$g_debugFlag) {
                                $newitem = New-Item $my_fullname -ItemType File | Out-Null
                                if ($newitem) {

                                }
                            }
                        }
                        return $true
                    }
                }
            }catch {
                throw
            }

            $false
        }

        function Rotate-Previous-Files-Incremental
        {
            # This function is only used for incremental index extensions, E.g. console.log.1 -> console.log.2. It is not used for date extensions.
            param (
                [Parameter(Mandatory=$True,Position=0)]
                [int]$rotate_compressed_files
            ,
                [Parameter(Mandatory=$True,Position=4)]
                [int]$max_index = 0
            )

            [Regex]$regex = if ($rotate_compressed_files) {
                                $my_previous_compressed_captures_regex
                            }else {
                                $my_previous_noncompressed_captures_regex
                            }
            $previous_name_prototype =  if ($compress) {
                                            $my_previous_compressed_name_prototype
                                        }else {
                                            $my_previous_name_prototype
                                        }
            $match = $regex.Match($previous_name_prototype)
            if ($match.success) {
                $prefix = $match.Groups['prefix'].Value
                $suffix = $match.Groups['suffix'].Value -as [int]
                $extension = if ($match.Groups['extension']) { $match.Groups['extension'].Value } else { '' }
                $compressextension = if ($match.Groups['compressextension']) { $match.Groups['compressextension'].Value } else { '' }

                if ($suffix) {
                    $SLASH = [IO.Path]::DirectorySeparatorChar
                    foreach ($i in @($max_index..0)) {
                        # Construct filenames with their index, and extension if provided
                        # E.g. D:\console.log.5 or D:\console.log.5.7z
                        $source_fullName = Join-Path $my_previous_directory "$prefix.$i$extension$compressextension"
                        # E.g. D:\console.log.6 or D:\console.log.6.7z
                        $destination_fullName = Join-Path $my_previous_directory "$prefix.$($i+1)$extension$compressextension"

                        # Rename old logs
                        Write-Verbose "Renaming $source_fullName to $destination_fullName (rotatecount $rotate, logstart $start, i $i)"
                        if ($g_debugFlag) { continue }
                        if (Test-Path $source_fullName) {
                            Try {
                                Move-Item -Path $source_fullName -Destination $destination_fullName -Force
                            }Catch {
                                Write-Error "$(Get-Exception-Message $_)"
                            }
                        }else {
                            Write-Verbose "Old log $source_fullName does not exist."
                        }
                    }
                }
            }
        }

        function Rename-File-Within-Compressed-Archive {
            # TODO: Not using this function for now, because this always recreates an archive, dumping a lot to the disk.

            # Only needed for 7z for now
            if ($compresscmd -notmatch '7za?') {
                return
            }

            Get-Files $my_previous_compressed_regex $my_previous_directory | & {
                begin {
                }process {
                    $directory =$_.Directory.FullName
                    $fullName = $_.FullName
                    $baseName = $_.BaseName

                    $params = @( 'rn', $fullName, '*', $baseName )
                    try {
                        Write-Verbose "Rename log inside compressed archive $fullName to $baseName"
                        if ($g_debugFlag) {
                            continue
                        }

                        $scriptblock = {
                            param ($cd, $cmd, [string[]]$params)
                            Set-Location $cd
                            Write-Output "cd: $cd"
                            Write-Output "cmd: $cmd"
                            Write-Output "params: "
                            $params | Out-String | ForEach-Object { Write-Output $_.Trim() }
                            & $cmd $params
                        }
                        $job = Start-Job -ScriptBlock $scriptblock -ArgumentList $directory,$compresscmd,$params -ErrorAction Stop
                        $output = Receive-Job -Job $job -Wait -ErrorAction Stop
                        if ($job.State -eq 'Failed') {
                            throw "Renaming failed because: $($job.ChildJobs[0].JobStateInfo.Reason.Message)"
                        }else {
                            Write-Verbose "Renaming log within compressed archive $fullName successful. Output: `n$output"
                        }
                    }catch {
                        #Write-Verbose "Renaming failed for log within compressed archive $fullName ."
                        Write-Verbose "Renaming log within compressed archive $fullName failed because $(Get-Exception-Message $_)."
                    }
                }
            }
        }

        function Compress-File {
            param (
                [Parameter(Mandatory=$True,Position=0)]
                [string]$compressed_fullname
            ,
                [Parameter(Mandatory=$True,Position=1)]
                [string]$filter
            )

            $compressed = $false

            # E.g. 7z.exe a -t7z D:\console.log.7z D:\console.log
            # E.g. gzip.exe D:\console.log
            $compressoptions = @( $compressoptions -split '\s' | Where-Object { $_.Trim() } )

            $params = if ($compresscmd -match '7z') {
                        $compressoptions + $compressed_fullname + $filter
                      }else {
                        $compressoptions + $filter
                      }
            # Remove empty parameters
            $params = $params | Where-Object { $_ }

            try {
                Write-Verbose "Compressing log with: $compresscmd"
                Write-Verbose "Compress command line: $compresscmd $( $params -join ' ' )"
                if ($g_debugFlag) {
                    return
                }

                $output = & $compresscmd $params
                if (Test-Path $compressed_fullname) {
                    Write-Verbose "Compression successful. Output: `n$output"

                    $compressed = $true
                }else {
                    Write-Verbose "Compression failed. Output: `n$output"
                    throw "Compressed file was not created."
                }

                # TODO: Not using jobs for now, because they are slow.
                <#
                $scriptblock = {
                    param ($cd, $cmd, [string[]]$params)
                    Set-Location $cd
                    #Write-Output "cd: $cd"
                    #Write-Output "cmd: $cmd"
                    #Write-Output "params: "
                    #$params | Out-String | ForEach-Object { Write-Output $_.Trim() }
                    & $cmd $params
                }
                $job = Start-Job -ScriptBlock $scriptblock -ArgumentList $logfile.Directory.FullName,$compresscmd,$params -ErrorAction Stop
                $output = Receive-Job -Job $job -Wait -ErrorAction Stop

                if ($job.State -eq 'Failed') {
                    throw "Compression failed because: $($job.ChildJobs[0].JobStateInfo.Reason.Message)"
                }else {
                    if (Test-Path $compressed_fullname) {
                        Write-Verbose "Compression successful. Output: `n$output"

                        $compressed = $true
                    }else {
                        Write-Verbose "Compression failed. Output: `n$output"
                        throw "Compressed file was not created."
                    }
                }
                #>
            }catch {
                Write-Verbose "Compression failed."
                throw "Compression failed because $(Get-Exception-Message $_)"
            }

            # Remove the previous file
            if ($compressed) {
                if (Test-Path $filter) {
                    Purge-File $filter
                    #Write-Verbose "Removed $filter"
                }
            }
        }

        function Uncompress-File {
            # TODO: Not using uncompress because we're not doing mail for now.
            param (
                [Parameter(Mandatory=$True,Position=0)]
                [string]$compressed_fullname
            )

            $uncompressed = $false

            # E.g. Extract as a file: 7z.exe x -t7z D:\console.log.7z
            # E.g. Extract to stdout: 7z.exe x -so D:\console.log.7z
            $uncompressoptions = $uncompressoptions.Split(' ') | Where-Object { $_.Trim() }
            $params = $uncompressoptions + $compressed_fullname

            try {
                $stdout = & $compresscmd $params
                if ($stdout) {
                    Write-Verbose "Uncompression successful. Output: `n$output"

                    # Store the file
                    $stdout | Out-File -Encoding utf8

                    $uncompressed = $true
                }else {
                    Write-Verbose "Uncompression failed. Output: `n$output"
                    throw "Uncompressed file was not created."
                }

                # TODO: Not using jobs for now, because they are slow.
                <#
                $scriptblock = {
                    param ($cd, $cmd, [string[]]$params)
                    Set-Location $cd
                    #Write-Output "cd: $cd"
                    #Write-Output "cmd: $cmd"
                    #Write-Output "params: "
                    #$params | Out-String | ForEach-Object { Write-Verbose $_.Trim() }
                    & $cmd $params
                }
                $job = Start-Job -ScriptBlock $scriptblock -ArgumentList (Get-Item $compressed_fullname).Directory.FullName,$uncompresscmd,$params -ErrorAction Stop
                $output = Receive-Job -Job $job -Wait -ErrorAction Stop
                if ($job.State -eq 'Failed') {
                    throw "Compression failed because: $($job.ChildJobs[0].JobStateInfo.Reason.Message)"
                }else {
                    if (Test-Path $compressed_fullname) {
                        Write-Verbose "Uncompression successful. Output: `n$output"
                        $uncompressed = $true
                    }else {
                        Write-Verbose "Uncompression failed. Output: `n$output"
                        throw "Uncompressed file was not created."
                    }
                }
                #>
            }catch {
                Write-Verbose "Uncompression failed."
                throw
            }

            # Remove the compressed file
            if ($uncompressed) {
                if (Test-Path $compressed_fullname) {
                    Remove-Item $compressed_fullname
                    Write-Verbose "Removed $compressed_fullname"
                }
            }
        }

        function Notify-Purge {
            param (
                [Parameter(Mandatory=$True,Position=0)]
                [string]$file_fullname
            )

            if ( !(Test-Path $file_fullname) ) {
                Write-Verbose "log $file_fullname doesn't exist -- won't try to dispose of it "
            }
        }

        function Purge-File {
            param (
                [Parameter(Mandatory=$True,Position=0)]
                [string]$file_fullname
            )

            if (Test-Path $file_fullname) {
                Write-Verbose "Removing old log $file_fullname"

                # Run preremove script
                if ($preremove) {
                    Write-Verbose "Running preremove script"
                    try {
                        Start-Script $preremove $file_fullname -ErrorAction $CallerEA
                    }catch {
                        throw "Failed to run preremove script. $(Get-Exception-Message $_)"
                    }
                }

                # Delete file
                if (!$g_debugFlag) {
                    Remove-Item $file_fullname
                }else {
                    # For debugging to simulate deleted file
                    $debug_my_prevfilespurged_fullnames.Add($file_fullname) | Out-Null
                }
            }
        }

        function Remove-Old-Files {
            param (
                [Parameter(Mandatory=$True,Position=0)]
                [AllowNull()]
                [Array]$files
            ,
                [Parameter(Mandatory=$True,Position=1)]
                [ValidateRange(0, [int]::MaxValue)]
                [int]$keep_count
            ,
                [Parameter(Mandatory=$True,Position=2)]
                [int]$oldest_is_first_when_name_sorted
            )

            $files_count =  if ($files) {
                                $files.Count
                            }else {
                                0
                            }
            if ($files_count) {
                if ($keep_count -ge $files_count) {
                    # If keeping 365 copies, and I only have 5.
                    # If keeping 5 copies, and I have 5
                    Write-Verbose "No more old files to remove $($_.FullName)"
                    return
                }

                $oldfiles_count = $files_count - $keep_count
                $oldfiles = if ($oldest_is_first_when_name_sorted) {
                    # Datetime. Exclude the last x items, when sorted by name ascending.
                    #$files | Sort-Object -Property Name | Select-Object -SkipLast $keep_count
                    $files | Sort-Object -Property Name | Select-Object -First $oldfiles_count
                }else {
                    # Descending index. Exclude the last x items, when sorted by name descending.
                    #$files | Sort-Object { [regex]::Replace($_.Name, '\d+', { $args[0].Value.PadLeft(20) }) } -Descending | Select-Object -SkipLast $keep_count
                    $files | Sort-Object { [regex]::Replace($_.Name, '\d+', { $args[0].Value.PadLeft(20) }) } -Descending | Select-Object -First $oldfiles_count
                }
                $oldfiles | ForEach-Object {
                    Write-Verbose "Removing $($_.FullName)"
                    Purge-File $_.FullName
                }
            }
        }

    }
    'HelperMethods' = [scriptblock]{
        ##########################
        # Object Private Helper Methods
        ##########################
        function Get-Files {
            param (
                [Parameter(Mandatory=$True,Position=0)]
                [string]$regex,
                [Parameter(Mandatory=$True,Position=1)]
                [string]$directory
            )
            Get-ChildItem $directory | Where-Object { $_.Name -match $regex }
        }
    }
}
# Methods
$LogObject | Add-Member -Name 'New' -MemberType ScriptMethod -Value {
    <# Constructs a Log Object (hashtable) representing a rotatable log. File, options and metadata (keys) mapped to their data.
    @{
        'Logfile' = $logfile
        'Options' = @{
            'compress' = $true;
            'rotate' = '5';
            ...
        }
        'Status' = @{
            'preprerotate' = $false
            'prerotate' = $false
            'rotate' = $false
            'postrotate' = $false
            'postpostrotate' = $false
            'rotation_datetime' = (Get-Date).ToLocalTime()
        }
        'Metadata' = @{
            my_name = 'console.log.';
            $my_extension = '.log';
            $my_stem = '.log';
            ...
        }
    }
    #>
    param ([System.IO.FileInfo]$logfile, [hashtable]$options, [string]$lastRotationDate)

    # Unpack the block's options into variables
    $options.Keys | ForEach-Object {
        Set-Variable -Name $_ -Value $options[$_]
    }

    #$VerbosePreference = $oldVerbosePreference

    # Builds a Constructed Log Object, for log files that should be rotated
    if ($logfile) {
        # E.g. '\' for WinNT, '/' for nix
        $SLASH = [IO.Path]::DirectorySeparatorChar

        # E.g. 'console.log' and 'D:\console.log'
        $my_name = $logfile.Name
        $my_fullname = $logfile.FullName

        # E.g. '.log'
        $my_extension = $logfile.Extension

        # Are we preserving the extension?
        $_preserve_extension = $extension -and $my_extension -and ($my_extension -eq $extension)
        Write-Verbose (& { if (!$_preserve_extension) {  "Not preserving extension." } else { "Preserving extension: $extension" } })

        # If we're preserving extension (which can consist of multiple .), we need the stam of the filename.
        # E.g. 'console'. It's the same as $_.BaseName
        $my_stem =  if ($extension) {
                        # E.g. '(.*)\.log' will capture 'console', when extension is '.log'
                        $my_stem_regex = [Regex]"(.*)$( [Regex]::Escape($extension) )$"
                        $matches = $my_stem_regex.Match($my_name)
                        $matches.Groups[1].Value
                     }else {
                        $logfile.BaseName
                     }

        # E.g. 'console\.log'
        $my_name_regex = [Regex]::Escape($my_name)

        # E.g. '\.log'
        $extension_regex = [Regex]::Escape($extension)

        # E.g. 'console'
        $my_stem_regex = [Regex]::Escape($my_stem)

        # Get current directory. E.g. 'D:\data'
        $my_directory = $logfile.Directory.FullName

        # Validate our olddir is a directory, and resolve it to an absolute path
        if ($olddir) {
            # Try relative location, then try absolute

            if ([System.IO.Path]::IsPathRooted($olddir)) {
                # Absolute path
            }else {
                # Relative path. Check for existance of an olddir in the same directory as the log file
                $olddir = Join-Path $my_directory $olddir
            }
            if ( !(Test-Path $olddir -PathType Container) ) {
                throw "Invalid olddir: $olddir. Not using olddir. Skipping log $($logfile.FullName)!"
            }
        }

        # Get previous directory. E.g. D:\data or D:\data\olddir
        $my_previous_directory = if ($olddir) { $olddir } else { $my_directory }

        # Check directories' permissions, skip over if insufficient permissions.
        foreach ($dir in $my_directory,$my_previous_directory) {
            try {
                $_outfile = Join-Path $dir ".test$(Get-Date -Format 'yyyyMMdd')"
                [io.file]::OpenWrite($_outfile).close()
                Remove-Item $_outfile
            }catch {
                throw "Insufficient permissions on $dir. Ensure the user $($env:username) has read and write permissions on the directory."
            }
        }

        # Build our glob patterns
        $my_date = ''
        $my_date_regex = ''
        if ($dateext -or !$dateext) {
            # Generate the date extension

            # Trim the strftime datetime format string
            $_dateformat_tmp = $dateformat
            $dateformat = $dateformat.Trim()
            Write-Verbose "Converted dateformat from '$_dateformat_tmp' to '$dateformat'"

            # Convert the strftime datetime format string (specifiers: %Y, %m, and %d) to a .NET datetime format string (specifiers: yyyy, mm, dd). Then use it to get the current datetime as a string
            # E.g. '2017-12-25'
            #$_format = $dateformat.replace('%Y', 'yyyy').replace('%m', 'MM').replace('%d', 'dd')
            #$my_date = Get-Date -Format $_format

            # Replace specifier %s with unix epoch first in the strftime datetime format string. Then use it to get the current datetime as a string.
            # E.g. '2017-12-25'
            $_unix_epoch = [Math]::Floor([decimal](Get-Date (Get-Date).ToUniversalTime() -uformat "%s"))
            $_uformat = $dateformat.replace('%s', $_unix_epoch)
            $my_date = Get-Date -UFormat $_uformat
            Write-Verbose "Determined date extension to be '$my_date'"

            # Determine glob
            # E.g. [0-9]{4}-[0-9]{2}-[0-9]{2}
            $_unix_epoch_length = $_unix_epoch.ToString().Length
            $my_date_regex = $dateformat.Replace('%Y', '[0-9]{4}').Replace('%m', '[0-9]{2}').Replace('%d', '[0-9]{2}').Replace('%s', "[0-9]{$_unix_epoch_length}")
            Write-Verbose "Determined date glob pattern: '$my_date_regex'"
        }

        # Build our previous name and previous fullname
        $my_previous_name = & {
            if ($_preserve_extension) {
                if ($dateext) {
                    # E.g. 'console-2017-11-20.log'
                    "$my_stem$my_date$extension"
                }else {
                    # E.g. 'console.1.log'
                    "$my_stem.$start$extension"
                }
            }else {
                if ($dateext) {
                    # E.g. 'console.log-2017-11-20'
                    "$my_name$my_date"
                }else {
                    # E.g. 'console.log.1'
                    "$my_name.$start"
                }
            }
        }
        $my_previous_fullname = Join-Path $my_previous_directory $my_previous_name

        # Determine the to-be-rotated log's compressed file name, if we are going to
        # E.g. 'D:\console.log.1.7z'
        $my_previous_compressed_fullname =  if ($compress) {
                                                "$my_previous_fullname$compressext"
                                            } else {
                                                ''
                                            }

        # Build prototype names
        # E.g. 'console.log.1'
        # E.g. 'console.log.1.7z'
        $my_previous_name_prototype = $my_previous_name
        $my_previous_compressed_name_prototype =    if ($compress) {
                                                        "$my_previous_name$compressext"
                                                    }

        $my_index_regex = "\d{1,$( $rotate.ToString().Length )}";
        $my_previous_noncompressed_regex = if ($_preserve_extension) {
                                                # E.g. '^console\-[0-9]{4}-[0-9]{2}-[0-9]{2}\.log$' or '^console\.\d{1,2}\.log$'
                                                if ($dateext) {
                                                    "^$my_stem_regex$my_date_regex$extension_regex$"
                                                }else {
                                                    "^$my_stem_regex\.$my_index_regex$extension_regex$"
                                                }
                                            }else {
                                                # E.g. '^console\.log\-[0-9]{4}-[0-9]{2}-[0-9]{2}$' or '^console\.log\.\d{1,2}$'
                                                if ($dateext) {
                                                    "^$my_name_regex$my_date_regex$"
                                                }else {
                                                    "^$my_name_regex\.$my_index_regex$"
                                                }
                                            }
        # E.g. '^console\.log\.\d{1,2}\.7z$' or '^console\.log\-[0-9]{4}-[0-9]{2}-[0-9]{2}\.7z$'
        $my_previous_compressed_regex = ($my_previous_noncompressed_regex -replace ".$") + [Regex]::Escape($compressext) + "$"

        # The same as above, but with capture groups.
        $my_previous_noncompressed_captures_regex = if ($_preserve_extension) {
                                                        # E.g. '^(?<prefix>console)(?<suffix>\-[0-9]{4}-[0-9]{2}-[0-9]{2})(?<extension>\.log)$' or '^(?<prefix>console)\.(?<suffix>\d{1,2})(?<extension>\.log)$'
                                                        if ($dateext) {
                                                            "^(?<prefix>$my_stem_regex)(?<suffix>$my_date_regex)(?<extension>$extension_regex)$"
                                                        }else {
                                                            "^(?<prefix>$my_stem_regex)\.(?<suffix>$my_index_regex)(?<extension>$extension_regex)$"
                                                        }
                                                    }else {
                                                        # E.g. '^(?<prefix>console\.log)(?<suffix>\-[0-9]{4}-[0-9]{2}-[0-9]{2})$' or '^(?<prefix>console\.log)\.(?<suffix>\d{1,2})$'
                                                        if ($dateext) {
                                                            "^(?<prefix>$my_name_regex)(?<suffix>$my_date_regex)$"
                                                        }else {
                                                            "^(?<prefix>$my_name_regex)\.(?<suffix>$my_index_regex)$"
                                                        }
                                                    }
        # E.g. '^(?<prefix>console\.log)\.(?<suffix>\d{1,2})(?<compressextension>\.7z)$' or '^(?<prefix>console\.log)(?<suffix>\-[0-9]{4}-[0-9]{2}-[0-9]{2})(?<compressextension>\.7z)$'
        $my_previous_compressed_captures_regex = ($my_previous_noncompressed_captures_regex -replace ".$") + "(?<compressextension>$( [Regex]::Escape($compressext) ))$"

        # Get all my existing files
        $my_prevfiles = if ($compress) {
                            # Get all my existing non-compressed files in this folder. E.g. filter by '*.7z'
                            Get-ChildItem $my_previous_directory | Where-Object { $_.Name -match $my_previous_compressed_regex }
                        }else {
                            # Get all my existing compressed files in this folder. E.g. 'console.log.x.7z', where x is a number
                            Get-ChildItem $my_previous_directory | Where-Object { $_.Name -match $my_previous_noncompressed_regex }
                        }

        # The expired file name. Only used for non-date extension.
        $my_expired_fullName =  if ($_preserve_extension) {
                                    if ($compress) {
                                        # E.g. 'D:\console.6.log.7z'
                                        Join-Path $my_previous_directory "$my_stem.$($start+$rotate)$extension$compressext"
                                    }else {
                                        # E.g. 'D:\console.6.log'
                                        Join-Path $my_previous_directory "$my_stem.$($start+$rotate)$extension"
                                    }
                                }else {
                                    if ($compress) {
                                        # E.g. 'D:\console.log.6.7z'
                                        Join-Path  $my_previous_directory "$my_name.$($start+$rotate)$compressext"
                                    }else {
                                        # E.g. 'D:\console.log.6'
                                        Join-Path $my_previous_directory "$my_name.$($start+$rotate)"
                                    }
                                }


        # Rotate? ALL CONDITIONS BELOW
        $should_rotate = & {

            # If forced, no processing of rotation conditions needed. Go ahead and rotate.
            if ($force) {
                return $true
            }

            # If never rotated before, go ahead
            #if (!$lastRotationDate) {
            #    return $true
            #}

            # Don't rotate if log file size is 0, and we specified to not rotate empty files.
            if (!$ifempty) {
                $my_size = $logfile.Length
                if (!$my_size) {
                    Write-Verbose "Will not rotate log: $my_name. File size is 0."
                    return $false
                }
            }

            # Don't rotate if my size is smaller than size threshold
            if ($size) {
                $my_size = ($logfile | Measure-Object -Property Length -Sum -Average -Maximum -Minimum).Sum
                if ($my_size -le (Get-Size-Bytes $size)) {
                    Write-Verbose "Will not rotate log: $my_name. File's size ($my_size) is less than defined ($size)."
                    return $false
                }
            }

            # Don't rotate if we haven't met time thresholds by daily / weekly / monthy / yearly options.
            # If minsize specified along with time thresholds, don't rotate if either time or minsize thresholds are unmet.
            if ($daily -or $weekly -or $monthly -or $yearly) {
                $time_interval_over = & {
                    # If it's our first time, considered to have met the time threshold
                    if (!$lastRotationDate) {
                        return $true
                    }

                    $_now_dt = (Get-Date).ToLocalTime()
                    # Not using CreationTime, but using state file now.
                    #$_my_newest_file = $my_prevfiles | Sort-Object -Property CreationTime -Descending | Select-Object -First 1
                    #$lastRotationDate = $_my_newest_file.CreationTime.ToLocalTime()
                    $_last_dt = Get-Date -Date $lastRotationDate
                    $_days_ago = (New-TimeSpan -Start $_last_dt -End $_now_dt ).Days
                    if ($daily) {
                        if ($_days_ago -ge 1) {
                            Write-Verbose "Time interval over. Last rotation occured a day or more ago. Last rotation: $($_last_dt.ToString('s'))"
                            return $true
                        }else {
                            Write-Verbose "Time interval not over. Last rotation occured less than a day ago. Last rotation: $($_last_dt.ToString('s'))"
                        }
                    }elseif ($weekly) {
                        if ($_days_ago -ge 7) {
                            Write-Verbose "Time interval over. Last rotation occured a week or more ago. Last rotation: $($_last_dt.ToString('s'))"
                            return $true
                        }elseif ( ($_days_ago -lt 7) -and ($_now_dt.DayOfWeek.value__ -lt $_last_dt.DayOfWeek.value__) ) {
                            Write-Verbose "Time interval over. Current weekday is less than weekday of last rotation."
                            return $true
                        }else {
                            Write-Verbose "Time interval not over. Last rotation occured less than a week ago. Last rotation: $($_last_dt.ToString('s'))"
                        }
                    }elseif ($monthly) {
                        if ($_now_dt.Month -gt $_last_dt.Month) {
                            Write-Verbose "Time interval over. This is the first time logrotate is run this month. "
                            return $true
                        }else {
                            Write-Verbose "Time interval not over. Last rotation already occured this month. Last rotation: $($_last_dt.ToString('s'))"
                        }
                    }elseif ($yearly) {
                        if ($_now_dt.Year -ne $_last_dt.Year) {
                            Write-Verbose "Time interval over. Last rotation occured on a different year as this year. Last rotation: $($_last_dt.ToString('s'))"
                            return $true
                        }else {
                            Write-Verbose "Time interval not over. Last rotation already occured this year. Last rotation: $($_last_dt.ToString('s'))"
                        }
                    }
                    $false
                }
                if ($time_interval_over) {
                    # If minsize is specified, both time and minsize thresholds will be considered
                    if ($minsize) {
                        $my_size = ($logfile | Measure-Object -Property Length -Sum -Average -Maximum -Minimum).Sum
                        Write-Verbose "my_size: $my_size"
                        if ($my_size -ge $minsize) {
                            # Minsize threshold met
                            Write-Verbose "Will rotate log: $my_name. Time interval over, and minsize met. File's size ($my_size) is less than minsize ($minsize)"
                            return $true
                        }else {
                            # Minsize threshold unmet
                            Write-Verbose "Will not rotate log: $my_name. Time interval over, but minsize not met. File's size ($my_size) is less than defined ($minsize)."
                            return $false
                        }
                    }else {
                        # No minsize specified. Only time threshold met.
                    }

                    # Time threshold met. Will rotate.
                    return $true
                }else {
                    # Haven't met time threshold. Don't rotate.
                    return $false
                }
            }

            # True by default. No conditions stopped us from moving on.
            $true
        }

        # Assign properties to the Log Object
        if ($should_rotate) {

            $_logObject = $LogObject.psobject.copy()
            $_logObject.Logfile = $logfile;
            $_logObject.Options = $options;
            $_logObject.Status = @{
                'preprerotate' = $false
                'prerotate' = $false
                'rotate' = $false
                'postrotate' = $false
                'postpostrotate' = $false
                'rotation_datetime' = (Get-Date).ToLocalTime()
            }
            $_logObject.Metadata = @{
                'my_name' = $my_name
                'my_extension' = $my_extension
                'my_stem' = $my_stem
                'my_directory' = $my_directory
                'my_previous_directory' = $my_previous_directory
                'my_previous_name' = $my_previous_name
                'my_previous_fullname' = $my_previous_fullname
                'my_date' = $my_date

                'my_name_regex' = $my_name_regex
                'my_date_regex' = $my_date_regex
                'my_previous_noncompressed_regex' = $my_previous_noncompressed_regex
                'my_previous_compressed_regex' = $my_previous_compressed_regex
                'my_previous_noncompressed_captures_regex' = $my_previous_noncompressed_captures_regex
                'my_previous_compressed_captures_regex' = $my_previous_compressed_captures_regex
                'my_previous_compressed_fullname' = $my_previous_compressed_fullname

                'my_prevfiles' = $my_prevfiles

                'my_previous_name_prototype' = $my_previous_name_prototype
                'my_previous_compressed_name_prototype' = $my_previous_compressed_name_prototype

                'my_expired_fullName' = $my_expired_fullName

                # For debug mode
                'debug_my_prevfilespurged_fullnames' = [System.Collections.ArrayList]@()

                'my_fullname' = $my_fullname
                'SLASH' = $SLASH
            }

            return $_logObject
        }
    }else {
        if ($nomissingok) {
            throw "Specified log $logfile is not a file."
        }
    }
    $null
}
$LogObject | Add-Member -Name 'PrePrerotate' -MemberType ScriptMethod -Value {
    # Unpack Object properties
    Set-Variable -Name 'logfile' -Value $this.Logfile
    $this.Options.Keys | ForEach-Object {
        Set-Variable -Name $_ -Value $this.Options[$_]
    }
    $this.Metadata.Keys | ForEach-Object {
        Set-Variable -Name $_ -Value $this.Metadata[$_]
    }

    # Unpack Object methods
    . $this.PrivateMethods
    . $this.HelperMethods

    Write-Verbose "rotating log $my_fullname, log->rotateCount is $rotate"
    Write-Verbose "date suffix '$my_date'"
    Write-Verbose "date glob pattern '$my_date_regex'"

    if (!$compress) {
        # Normal rotation without compression

        if (!$dateext) {
            # Rotate all previous files
            # D:\console.log.1.7z -> D:\console.log.2.7z
            Rotate-Previous-Files-Incremental 0 ($start+$rotate-1)

            Notify-Purge $my_expired_fullName

            $this.Status.preprerotate = $true
        }else {
            # Delete old logs
            if ($rotate -gt 0) {
                Remove-Old-Files (Get-Files $my_previous_noncompressed_regex $my_previous_directory) $rotate 1
            }
            if (Test-Path $my_previous_fullname) {
                Write-Verbose "Destination $my_previous_fullname already exists, skipping rotation"
            }else {
                $this.Status.preprerotate = $true
            }
        }
    }elseif ($compress) {
        # Compress

        if (!$dateext) {

            if (!$delaycompress) {
                # Rotate all previous compressed files
                # D:\console.log.1.7z -> D:\console.log.2.7z
                Rotate-Previous-Files-Incremental 1 ($start+$rotate-1)

                # TODO: Not using for now. See the comments in function.
                #Rename-File-Within-Compressed-Archive

                Notify-Purge $my_expired_fullName

                $this.Status.preprerotate = $true
            }else {
                # Flag to indicate safe to rotate
                $_skip_rotate = $false
                if (Test-Path $my_previous_fullname) {
                    if (Test-Path $my_previous_compressed_fullname) {
                        # File exists.
                        Write-Verbose "Error creating output file $my_previous_compressed_fullname : file exists"
                        $_skip_rotate = $true
                    }else {
                        # Compress previous file, Remove compression source file
                        # D:\console.log.1 -> D:\console.log.1.7z
                        Compress-File $my_previous_compressed_fullname $my_previous_fullname
                    }
                }

                if ($_skip_rotate) {
                    Notify-Purge $my_expired_fullName
                }else {
                    # Rotate all previous compressed files
                    # D:\console.log.1.7z -> D:\console.log.2.7z
                    Rotate-Previous-Files-Incremental 1 ($start+$rotate-1)

                    # Disabled for now, because this always recreates an archive, dumping a lot to the disk.
                    #Rename-File-Within-Compressed-Archive

                    Notify-Purge $my_expired_fullName

                    $this.Status.preprerotate = $true
                }
            }
        }else {

            # Date extension
            if (!$delaycompress) {

                # Delete old logs
                if ($rotate -gt 0) {
                    Remove-Old-Files (Get-Files $my_previous_compressed_regex $my_previous_directory) $rotate 1
                }

                if (Test-Path $my_previous_compressed_fullname) {
                    # File exists.
                    Write-Verbose "Destination file $my_previous_compressed_fullname already exists, skipping rotation"
                }else {
                    $this.Status.preprerotate = $true
                }
            }else {
                # Compress any uncompressed previous files
                $_skip_rotate = $false
                Get-Files $my_previous_noncompressed_regex $my_previous_directory | ForEach-Object {
                    # Skip over the rest of pipeline
                    if ($_skip_rotate) {
                        return
                    }

                    # E.g. console.log-2017-11-25
                    $_fullname = $_.FullName
                    # E.g. console.log-2017-11-25.7z
                    $_compressed_fullname = "$_fullname$compressext"

                    if ( Test-Path $_compressed_fullname ) {
                        Write-Verbose "Error creating output file $_compressed_fullname`: File exists"

                        $_skip_rotate = $true
                    }else {
                        # Compress previous file, Remove compression source file
                        # D:\console.log-2017-11-25 -> D:\console.log-2017-11-25.7z
                        Compress-File $_compressed_fullname $_fullname
                    }
                }

                if ($_skip_rotate) {
                    # Don't proceed any further
                }else {
                    # Delete old logs
                    if ($rotate -gt 0) {
                        Remove-Old-Files (Get-Files $my_previous_compressed_regex $my_previous_directory) $rotate 1
                    }
                    if ( (Test-Path $my_previous_fullname) -or (Test-Path $my_previous_compressed_fullname) ) {
                        # File exists.
                        Write-Verbose "Destination file $my_previous_fullname already exists, skipping rotation"
                    }else {
                        $this.Status.preprerotate = $true
                    }
                }
            }

        } # End if ($dateext)

    } # End if ($compress)

    # Removed this - Script will spit stdout on the Pipeline
    #$this.Status.preprerotate
}
$LogObject | Add-Member -Name 'Prerotate' -MemberType ScriptMethod -Value {
    # Unpack Object properties
    $prerotate = $this.Options['prerotate']
    $my_fullname = $this.Metadata['my_fullname']

    if ($prerotate) {
        Write-Verbose "Running prerotate script"
        try {
            Start-Script $prerotate $my_fullname -ErrorAction Stop
        }catch {
            throw "Failed to run prerotate script. $(Get-Exception-Message $_)"
        }

        $this.Status.prerotate = $true
    }

    # Removed this - Script will spit stdout on the Pipeline
    #$this.Status.prerotate
}
$LogObject | Add-Member -Name 'RotateMainOnly' -MemberType ScriptMethod -Value {
    # Unpack Object properties
    Set-Variable -Name 'logfile' -Value $this.Logfile
    $this.Options.Keys | ForEach-Object {
        Set-Variable -Name $_ -Value $this.Options[$_]
    }
    $this.Metadata.Keys | ForEach-Object {
        Set-Variable -Name $_ -Value $this.Metadata[$_]
    }

    # Unpack Object methods
    . $this.PrivateMethods

    $this.Status.rotate = Rotate-Main
    # Removed this - Script will spit stdout on the Pipeline
    #$this.Status.rotate
}
$LogObject | Add-Member -Name 'Postrotate' -MemberType ScriptMethod -Value {
    # Unpack Object properties
    $postrotate = $this.Options['postrotate']
    $my_fullname = $this.Metadata['my_fullname']

    if ($postrotate) {
        Write-Verbose "Running postrotate script"
        try {
            Start-Script $postrotate $my_fullname -ErrorAction $CallerEA
        }catch {
            throw "Failed to run postrotate script. $(Get-Exception-Message $_)"
        }
        $this.Status.postrotate = $true
    }

    # Removed this - Script will spit stdout on the Pipeline
    #$this.Status.postrotate
}
$LogObject | Add-Member -Name 'PostPostRotate' -MemberType ScriptMethod -Value {
    # Unpack Object properties
    Set-Variable -Name 'logfile' -Value $this.Logfile
    $this.Options.Keys | ForEach-Object {
        Set-Variable -Name $_ -Value $this.Options[$_]
    }
    $this.Metadata.Keys | ForEach-Object {
        Set-Variable -Name $_ -Value $this.Metadata[$_]
    }

    # Unpack Object methods
    . $this.PrivateMethods
    . $this.HelperMethods

    if (!$compress) {
        # Normal rotation without compression

        if (!$dateext) {
            # Non-dateext: we'll just purge a single file. At least that's how it works the actual logrotate.

            # Remove expired file
            Purge-File $my_expired_fullName

            $this.Status.postpostrotate = $true
        }else {
            # Remove expired files
            if ($rotate -gt 0) {
                $keep_prev_count = $rotate
                $prev_files = Get-Files $my_previous_noncompressed_regex $my_previous_directory | Where-Object {
                                                                                                        !$g_debugFlag -or
                                                                                                        ($g_debugFlag -and $_.FullName -notin $debug_my_prevfilespurged_fullnames )
                                                                                                    }

                Remove-Old-Files $prev_files $keep_prev_count 1
            }

            $this.Status.postpostrotate = $true
		}
    }elseif ($compress) {
        # Compress

        if (!$dateext) {
            # Non-dateext: we'll just purge a single file. At least that's how it works the actual logrotate.

            if (!$delaycompress) {
                # Compress previous file, Remove compression source file
                # D:\console.log.1 -> D:\console.log.1.7z
                Compress-File $my_previous_compressed_fullname $my_previous_fullname

			    # Remove expired file
                Purge-File $my_expired_fullName
            }else {
				# Remove expired file
                Purge-File $my_expired_fullName
            }
        }else {
            $keep_prev_compressed_count = $rotate

            # Date extension
            if (!$delaycompress) {
                # Compress previous file, Remove compression source file
                # console.log.1 -> console.log.1.7z
                Compress-File $my_previous_compressed_fullname $my_previous_fullname
            }else {
                if ($rotate -gt 0) {
                    # One log is non-compressed because it's delayed.
                    $keep_prev_compressed_count = $rotate - 1
                }
            }

            # Delete old compressed logs
            if ($rotate -gt 0) {
                $prev_files = Get-Files $my_previous_compressed_regex $my_previous_directory | Where-Object {
                    !$g_debugFlag -or
                    ($g_debugFlag -and $_.FullName -notin $debug_my_prevfilespurged_fullnames )
                }
                Remove-Old-Files $prev_files $keep_prev_compressed_count 1
            }

        } # End if ($dateext)


        $this.Status.postpostrotate = $true

    } # End if ($compress)

    # Removed this - Script will spit stdout on the Pipeline
    #$this.Status.postpostrotate
}
