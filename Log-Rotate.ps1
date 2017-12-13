###############################################################################
# Declare your config inside the Here-String. An optimal sample is provided.
# For a list of configuration options, refer to logrotate manual:
#     https://linux.die.net/man/8/logrotate
###############################################################################
$myConfig = @'
##### Start adding Config here #####

# If a directory is specified with a wildcard (*), all files within it are rotated. 
# If a file is specified, that file will be rotated.
# Use double-quotes if path has spaces.
# Separate entries with spaces. 

# Global options
nocompress
size 100k

# Block options - Windows
"C:\inetpub\logs\iis\mylogs\*.log" D:\console.log {
    rotate 3650
    size 1M
	extension .log
	compress
    compresscmd C:\Program Files\7-Zip\7z.exe
    compressoptions a -t7z
	compressext .7z
    dateext
	delaycompress
	minsize 1M
    sharedscripts
    prerotate
        Write-Host "I am a script and my log file's full path is: $($Args[0]). I could email my log using Powershell"
        $content = Get-Content $Args[0]
        #Send-MailMessage ..... 
    endscript
}

# Block options - *nix
/var/log/nginx/mylogs/*.log  {
    compresscmd 7z
    compressoptions a -t7z
    compressext .7z
    postrotate
        /usr/bin/killall -HUP httpd
        echo "I am a script and my log file's full path is ${0}"
        #sendmail -s .....
    endscript
}

##### End adding #####
'@

#####################
#  Helper functions #
#####################
function Get-Size-Bytes {
    # Returns a size specified with a unit (E.g. 100, 100k, 100M, 100G) into bytes without a unit
    param ([string]$size_str)
    if ($g_debugFlag -band 2) { Write-Debug "[Get-Size-Bytes] Verbose stream: $VerbosePreference" }
    if ($g_debugFlag -band 2) { Write-Debug "[Get-Size-Bytes] Debug stream: $DebugPreference" } 
    if ($g_debugFlag -band 2) { Write-Debug "[Get-Size-Bytes] Erroraction: $ErrorActionPreference" }

    if ($size_str -match '(?:[0-9]+|[0-9]+(?:k|M|G))$') {
        $size_unit = $size_str -replace '[0-9]+'
        [int64]$size = $size_str -replace $size_unit
        switch($size_unit) {
            "" { $size = $size }
            "k" { $size = $size * 1024 }
            "M" { $size = $size * 1024 * 1024 }
            "G" { $size = $size * 1024 * 1024 * 1024 }
        }
    }else {
        #Write-Error "The size specified was '$size_str'. Size should be specified in quantity and unit, e.g. '100k', or '100M'. Only units 'k', 'M', or 'G' are allowed." -ErrorAction Stop
        throw "The size specified was '$size_str'. Size should be specified in quantity and unit, e.g. '100k', or '100M'. Only units 'k', 'M', or 'G' are allowed."
        #Write-Error -Exception (New-Object Exception "The size specified was '$size_str'. Size should be specified in quantity and unit, e.g. '100k', or '100M'. Only units 'k', 'M', or 'G' are allowed.") -ErrorAction Stop
    }
    $size
}
function Get-Exception-Message ($ErrorRecord) {
    function Get-InnerExceptionMessage ($Exception) {
        if ($Exception.InnerException) {
            Get-InnerExceptionMessage $Exception.InnerException
        }else {
            $Exception.Message
        }
    }
    $Message = Get-InnerExceptionMessage $ErrorRecord.Exception
    $Message  + "`nStacktrace:`n" + $ErrorRecord.Exception.ErrorRecord.ScriptStackTrace   
}
function likeIn ([string]$string, [string[]]$wildcardblobs) {
    foreach ($wildcardblob in $wildcardblobs) {
        if ($string -like $wildcardblob) {
            return $true
        }
    }
    $false
}
function Start-Script {
    [CmdletBinding()]
    param (
        [AllowNull()]
        [string]$script,
        [string]$file_FullName
    )

    begin {
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
        if ($g_debugFlag -band 2) { Write-Verbose "[Start-Script] callerEA: $callerEA" }
        if ($g_debugFlag -band 2) { Write-Verbose "[Start-Script] ErrorActionPreference: $ErrorActionPreference" } 
    }

    process {
        try {
            Write-Verbose "Running script with arg $file_FullName : `n$script"
            $OS = $ENV:OS
            if ($OS -eq "Windows_NT") {
                # & operator: When we use & $cmd $param, powershell wraps args containing spaces with double-quotes, so we need escape inner double-quotes
                $cmd =  if ( Get-Command 'powershell' -ErrorAction SilentlyContinue ) {
                            "powershell"
                        }elseif ( Get-Command 'pwsh' -ErrorAction SilentlyContinue ) {
                            "pwsh"
                        }
                $scriptblock = [scriptblock]::Create($script)
                #$params = '-Command', $scriptblock, '-Args', @($file_FullName)
                $output = & $cmd -Command $scriptblock -Args @($file_FullName)
            }else {
                # E.g. sh -c 'echo ${0}' 'D:\console.log'
                
                # & operator: When we use & $cmd $param, powershell wraps args containing spaces with double-quotes, so we need escape inner double-quotes
                $cmd = 'sh'
                $params = '-c', $script.Replace('"', '\"'), $file_FullName
                $output = & $cmd $params

                # TODO: Not using jobs for now, because they are slow.
                #$script = "sh -c '$script' `$args[0]"
            }
       
            #
           
            Write-Verbose "Script output: `n$output"

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
        }catch {
            Write-Error "Failed to execute script for $file_FullName. `nError: $_ `nScript (possibly with errors): $script" -ErrorAction $callerEA
        }
    }
}
# Class Helper - Unused for now
function Extend-Class {
    param ($classObject, [PSModuleInfo]$importedModule)

    $importedModule.ExportedFunctions.Keys | ForEach-Object {
        Write-Verbose "Key: $_"
        Write-Verbose "Function: $((Get-item function:$_).Definition)"
        $scriptblock = [Scriptblock]::Create( (Get-item function:$_).Definition ) 
        $classObject | Add-Member -Name $_ -MemberType ScriptMethod -Value $scriptblock
    }
}

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
                throw $_
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
                        # E.g. console.log.5 or console.log.5.7z
                        $source_fullName = "$my_previous_directory$SLASH$prefix.$i$extension$compressextension"
                        # E.g. console.log.6 or console.log.6.7z
                        $destination_fullName = "$my_previous_directory$SLASH$prefix.$($i+1)$extension$compressextension"	
                
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

            # E.g. 7z.exe a -t7z console.log.7z console.log
            # E.g. gzip.exe console.log
            $compressoptions = $compressoptions.Split(' ') | Where-Object { $_.Trim() } 
            
            $params = if ($compresscmd -match '7z') {
                        $compressoptions + $compressed_fullname + $filter
                      }else {
                        $compressoptions + $compressed_fullname
                      }
            # Remove empty parameters
            $params = $params | Where-Object { $_ }

            try {
                Write-Verbose "Compressing log with: $compresscmd"
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

            # E.g. Extract as a file: 7z.exe x -t7z console.log.7z
            # E.g. Extract to stdout: 7z.exe x -so console.log.7z
            $uncompressoptions = $uncompressoptions.Split(' ') | Where-Object { $_.Trim() } 
            $params = $uncompressoptions + $compressed_fullname
        
            try {
                $stdout = & $compresscmd $params
                if ($stdout) {
                    Write-Verbose "Uncompression successful. Output: `n$output"

                    # Store the file
                    $stdout | Out-File -Encoding utf8 -NoNewline

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
                        if (!$g_debugFlag) {
                            Start-Script $preremove $file_fullname -ErrorAction Continue
                        }
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

    if ($g_debugFlag -band 2) { Write-Debug "[LogObject][New] Verbose stream: $VerbosePreference" }
    if ($g_debugFlag -band 2) { Write-Debug "[LogObject][New] Debug stream: $DebugPreference" } 
    if ($g_debugFlag -band 2) { Write-Debug "[LogObject][New] Erroraction: $ErrorActionPreference" } 

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
                        # E.g. '(.*)\.log' will capture 'console', when extension is 'log'
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
            Set-Location $my_directory
            # Try relative location, then try absolute
            if (Test-Path $olddir -PathType Container) {
                $olddir = (Get-Item $olddir).FullName
            }else {
                $olddir = "$($logfile.Directory.FullName)$SLASH$olddir"
                if ( !(Test-Path $olddir -PathType Container) ) {
                    throw "Invalid olddir: $olddir. Not using olddir. Skipping log $($logfile.FullName)!"
                }
            }
        }

        # Get previous directory. E.g. D:\data or D:\data\olddir
        $my_previous_directory = if ($olddir) { $olddir } else { $my_directory }

        # Check directories' permissions, skip over if insufficient permissions.
        foreach ($dir in $my_directory,$my_previous_directory) {
            try {
                $_outfile = "$dir$SLASH.test$(Get-Date -Format 'yyyyMMdd')"
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
        $my_previous_fullname = "$my_previous_directory$SLASH$my_previous_name"
        
        # Determine to-be-rotated log's compressed file name, if we are going to
        # E.g. 'console.log.1.7z'
        $my_previous_compressed_fullname =  if ($compress) { 
                                                "$my_previous_fullname$compressext" 
                                            } else { 
                                                '' 
                                            }

        # Build prototype names
        $my_previous_name_prototype = $my_previous_name
        $my_previous_compressed_name_prototype =    if ($compress) { 
                                                        "$my_previous_name$compressext" 
                                                    }

        $my_index_regex = "\d{1,$( $rotate.ToString().Length )}";
        $my_previous_noncompressed_regex = if ($_preserve_extension) {
                                                # E.g. '^console\-[0-9]{4}-[0-9]{2}-[0-9]{2}\.log$' or '^console\.\d{1,2,3}\.log$'
                                                if ($dateext) {
                                                    "^$my_stem_regex$my_date_regex$extension_regex$"
                                                }else {
                                                    "^$my_stem_regex\.$my_index_regex$extension_regex$"
                                                }
                                            }else {
                                                # E.g. '^console\.log\-[0-9]{4}-[0-9]{2}-[0-9]{2}$' or '^console\.log\.\d{1,2,3}$'
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
                                                        # E.g. '^console\-[0-9]{4}-[0-9]{2}-[0-9]{2}\.log$' or '^console\.\d{1,2,3}\.log$'
                                                        if ($dateext) {
                                                            "^(?<prefix>$my_stem_regex)(?<suffix>$my_date_regex)(?<extension>$extension_regex)$"
                                                        }else {
                                                            "^(?<prefix>$my_stem_regex)\.(?<suffix>$my_index_regex)(?<extension>$extension_regex)$"
                                                        }
                                                    }else {
                                                        # E.g. '^console\.log\-[0-9]{4}-[0-9]{2}-[0-9]{2}$' or '^console\.log\.\d{1,2,3}$'
                                                        if ($dateext) {
                                                            "^(?<prefix>$my_name_regex)(?<suffix>$my_date_regex)$"
                                                        }else {
                                                            "^(?<prefix>$my_name_regex)\.(?<suffix>$my_index_regex)$"
                                                        }
                                                    }
        # E.g. '^console\.log\.\d{1,2}\.7z$' or '^console\.log\-[0-9]{4}-[0-9]{2}-[0-9]{2}\.7z$'
        $my_previous_compressed_captures_regex = ($my_previous_noncompressed_captures_regex -replace ".$") + "(?<compressextension>$( [Regex]::Escape($compressext) ))$"

        # Get all my existing files
        $my_prevfiles = if ($compress) {
                            # Get all my existing non-compressed files in this folder. E.g. filter by '*.7z'
                            Get-ChildItem $my_previous_directory | Where-Object { $_.Name -match $my_previous_compressed_regex }
                        }else {
                            # Get all my existing compressed files in this folder. E.g. 'console.log.x.7z', where x is a number
                            Get-ChildItem $my_previous_directory | Where-Object { $_.Name -match $my_previous_noncompressed_regex }
                        }
        
        # The expired file name. Only used for non-date extension
        $my_expired_fullName =  if ($_preserve_extension) {
                                if ($compress) {
                                    "$my_previous_directory$SLASH$my_stem.$($start+$rotate)$extension$compressext"
                                }else {
                                    "$my_previous_directory$SLASH$my_stem.$($start+$rotate)$extension"
                                }
                            }else {
                                if ($compress) {
                                    "$my_previous_directory$SLASH$my_name.$($start+$rotate)$compressext"
                                }else {
                                    "$my_previous_directory$SLASH$my_name.$($start+$rotate)"
                                }
                            }


        # Rotate? ALL CONDITIONS BELOW
        $should_rotate = & {

            # Don't rotate if log file size is 0, and we specified to not rotate empty files.
            if (!$ifempty) {
                $my_size = $logfile.Length
                if (!$my_size) {
                    Write-Verbose "Will not rotate log: $my_name. File size is 0."
                    return $false
                }
            }

            # If forced, don't process any conditions.
            if ($force) {
                return $true
            }
            
            # If never rotated before, go ahead
            #if (!$lastRotationDate) { 
            #    return $true 
            #}

            # Don't rotate if my size is smaller than size threshold
            if ($size) {
                $my_size = ($logfile | Measure-Object -Property Length -Sum -Average -Maximum -Minimum).Sum
                if ($my_size -le (Get-Size-Bytes $size)) {
                    Write-Verbose "Will not rotate log: $my_name. File's size ($my_size) is less than defined ($size)."
                    return $false
                }
            }

            # Rotate only if we haven't already done so before as specified by daily / weekly / monthy / yearly options
            if ($daily -or $weekly -or $monthly -or $yearly) {
                $time_interval_over = & {
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
                    # If minsize is specified, both time interval and minsize will be considered
                    if ($minsize) {
                        $my_size = ($logfile | Measure-Object -Property Length -Sum -Average -Maximum -Minimum).Sum
                        Write-Verbose "my_size: $my_size"
                        if ($my_size -ge $minsize) {
                            # minsize is over
                            Write-Verbose "Will rotate log: $my_name. Time interval over, and minsize met. File's size ($my_size) is less than minsize ($minsize)"
                            return $true
                        }else {
                            Write-Verbose "Will not rotate log: $my_name. Time interval over, but minsize not met. File's size ($my_size) is less than defined ($minsize)."
                            return $false
                        }
                    }else {
                        # No minsize specified. Time interval over is all there is.
                    }

                    # Time interval is over. Will rotate.
                    return $true
                }
            }

            # False by default
            $false
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
        }else {
            Write-Error "  log does not need rotating."
        }
    }else {
        if ($nomissingok) {
            Write-Error "Specified log $logfile is not a file. Skipping rotation."
        }
    }
    $null
}
$LogObject | Add-Member -Name 'PrePrerotate' -MemberType ScriptMethod -Value {
    if ($g_debugFlag -band 2) { Write-Debug "[LogObject][PrePrerotate] Verbose stream: $VerbosePreference" }
    if ($g_debugFlag -band 2) { Write-Debug "[LogObject][PrePrerotate] Debug stream: $DebugPreference" } 
    if ($g_debugFlag -band 2) { Write-Debug "[LogObject][PrePrerotate] Erroraction: $ErrorActionPreference" }

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

    $this.Status.preprerotate
}
$LogObject | Add-Member -Name 'Prerotate' -MemberType ScriptMethod -Value {
    if ($g_debugFlag -band 2) { Write-Debug "[LogObject][Prerotate] Verbose stream: $VerbosePreference" }
    if ($g_debugFlag -band 2) { Write-Debug "[LogObject][Prerotate] Debug stream: $DebugPreference" } 
    if ($g_debugFlag -band 2) { Write-Debug "[LogObject][Prerotate] Erroraction: $ErrorActionPreference" }

    # Unpack Object properties
    $prerotate = $this.Options['prerotate']
    $my_fullname = $this.Metadata['my_fullname']

    if ($prerotate) {
        Write-Verbose "Running prerotate script"
        try {
            if (!$g_debugFlag) {
                Start-Script $prerotate $my_fullname -ErrorAction Stop
            }
        }catch {
            throw "Failed to run prerotate script. $(Get-Exception-Message $_)" 
        }

        $this.Status.prerotate = $true
    }

    $this.Status.prerotate
}
$LogObject | Add-Member -Name 'RotateMainOnly' -MemberType ScriptMethod -Value {
    if ($g_debugFlag -band 2) { Write-Debug "[LogObject][RotateMainOnly] Verbose stream: $VerbosePreference" }
    if ($g_debugFlag -band 2) { Write-Debug "[LogObject][RotateMainOnly] Debug stream: $DebugPreference" } 
    if ($g_debugFlag -band 2) { Write-Debug "[LogObject][RotateMainOnly] Erroraction: $ErrorActionPreference" }

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
    $this.Status.rotate
}
$LogObject | Add-Member -Name 'Postrotate' -MemberType ScriptMethod -Value {
    if ($g_debugFlag -band 2) { Write-Debug "[LogObject][Postrotate] Verbose stream: $VerbosePreference" }
    if ($g_debugFlag -band 2) { Write-Debug "[LogObject][Postrotate] Debug stream: $DebugPreference" } 
    if ($g_debugFlag -band 2) { Write-Debug "[LogObject][Postrotate] Erroraction: $ErrorActionPreference" }
    
    # Unpack Object properties
    $postrotate = $this.Options['postrotate']
    $my_fullname = $this.Metadata['my_fullname']

    if ($postrotate) {
        Write-Verbose "Running postrotate script"
        try {
            if (!$g_debugFlag) {
                Start-Script $postrotate $my_fullname -ErrorAction Stop
            }
        }catch {
            throw "Failed to run postrotate script. $(Get-Exception-Message $_)" 
        }
        $this.Status.postrotate = $true
    }

    $this.Status.postrotate
}
$LogObject | Add-Member -Name 'PostPostRotate' -MemberType ScriptMethod -Value {
    if ($g_debugFlag -band 2) { Write-Debug "[LogObject][PostPostRotate] Verbose stream: $VerbosePreference" }
    if ($g_debugFlag -band 2) { Write-Debug "[LogObject][PostPostRotate] Debug stream: $DebugPreference" } 
    if ($g_debugFlag -band 2) { Write-Debug "[LogObject][PostPostRotate] Erroraction: $ErrorActionPreference" }

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

    $this.Status.postpostrotate
}

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
    The full path to a Log-Rotate state file to use for previously rotated Logs. The default location of the state file is within Log-Rotate's containing directory.
    
    .PARAMETER Usage
    Prints Usage information .
    
    .EXAMPLE
    Log-Rotate -Debug -Config 'C:\configs\'

    .EXAMPLE
    Log-Rotate -Debug -Config '/etc/Log-Rotate/configs/' -State '/var/lib/Log-Rotate/status'

    .LINK

    .NOTES
    *logrotate manual: https://linux.die.net/man/8/logrotate
    
    The command line is identical to the actual logrotate utility, if aliases are used. If using full parameters, only optional (-mail, -state) and miscellaneous (-usage, -help) parameters use one instead of two dashes. (i.e. -mail instead of --mail)
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

    # Debug bitwise flag (for developers)
    # 0 - Off
    # 1 - On, script does not change files. Calling Log-Rotate with -Debug will switch this to 1.
    # 2 - On, verbose mode. Implies (1). This is NOT related to calling Log-Rotate with -Verbose, but strictly for debugging messages.
    $g_debugFlag = 0

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
        $g_debugFlag = if ($g_debugFlag) { $g_debugFlag } else { 1 }
    }else { 
         # If we're not using the -debug flag, debug should stay silent instead of prompting. 
        $DebugPreference = 'SilentlyContinue' 
    }

    # Prints miscellaneous information and exits
    $LogRotateVersion = '1.00'
    if ($Version) {
        Write-Output "Log-Rotate 1.00"
        exit
    }
    if ($Help) {
        Write-Output (Get-Help Log-Rotate -Full)
        exit
    }
    if ($Usage) {
        Write-Output (Get-Help Log-Rotate)
        exit
    }
    function Compile-Full-Config {
        param ([string]$MultipleConfig)


        if ($g_debugFlag -band 2) { Write-Debug "[Compile-Full-Config] Verbose stream: $VerbosePreference" }
        if ($g_debugFlag -band 2) { Write-Debug "[Compile-Full-Config] Debug stream: $DebugPreference" } 
        if ($g_debugFlag -band 2) { Write-Debug "[Compile-Full-Config] Erroraction: $ErrorActionPreference" }

        [Scriptblock]$matchEvaluator = {
            param ($match)

            $include_path = $match.Groups[1].Value.Trim()
            # Check if it's a file or directory
            if ($include_path -and (Test-Path $include_path))  {
                $item = Get-Item $include_path    
                
                if ($item.PSIsContainer) {
                    # It's a directory. Include content of all files inside it
                    $content = ""
                    Get-ChildItem $item | ForEach-Object {
                        Write-Verbose "CONFIG: Including file $($item.FullName)"
                        Write-Verbose "CONFIG: Reading file $($item.FullName)"
                        $content += Get-Content $_.FullName -Raw
                    }
                }else {
                    # It's a single file. Include its content
                    Write-Verbose "CONFIG: Including file $($item.FullName)"
                    Write-Verbose "CONFIG: Reading file $($item.FullName)"
                    $content = Get-Content $include_path -Raw 
                }
            }else {
                Write-Verbose "CONFIG: Ignoring included path $include_path because it is invalid."
            }

            # Return the replacement value
            if ($content) {
                "`n$content"
            }
        }
  
        # Remove all comments (i.e. starting with '#')
        [Regex]$remove_comments_regex = '#.*'
        $MultipleConfig = $remove_comments_regex.Replace($MultipleConfig, '')
        
        # Remove all within-block 'include' directives
        [Regex]$include_regex = '({[^}]*?)(include[^\n]*)([^}]*})'
        $MultipleConfig = $include_regex.Replace($MultipleConfig, '$1$3')

        # Insert all 'include' directives' paths' content
        [Regex]$include_regex = '\s*include([^\n]*)'
        $MultipleConfig = $include_regex.Replace($MultipleConfig, $matchEvaluator)

        # Remove all comments (i.e. starting with '#')
        [Regex]$remove_comments_regex = '#.*'
        $MultipleConfig = $remove_comments_regex.Replace($MultipleConfig, '')

        # Return compiled config
        $MultipleConfig
    }
    function Validate-Full-Config {
        param ([string]$FullConfig)

        if ($g_debugFlag -band 2) { Write-Debug "[Validate-Full-Config] Verbose stream: $VerbosePreference" }
        if ($g_debugFlag -band 2) { Write-Debug "[Validate-Full-Config] Debug stream: $DebugPreference" } 
        if ($g_debugFlag -band 2) { Write-Debug "[Validate-Full-Config] Erroraction: $ErrorActionPreference" }

        function Get-LinesAround([string[]]$lines, [int]$line_number) {
            $start = 0
            $around = 10
            $end = $lines.count - 1

            if ( ($line_number -le $around) ) {
                $dumpstart = $start
            }else {
                $dumpstart = $line_number - $around
            }

            if ( ($line_number -ge ($end - $around)) ) {
                $dumpend = $end
            }else {
                $dumpend = $line_number + $around
            }

            $dump = [System.Collections.ArrayList]@()
            foreach ($i in ($dumpstart..$dumpend) ) {
                if (  ($i -eq $line_number )  -or  ($i -eq ($line_number - 1))  ) {
                    $dump.Add("NEAR HERE -------->") | Out-Null
                }
                $dump.Add($lines[$i]) | Out-Null
            }
            $dump
        }

        # Ignore firstaction,lastaction,prerotate,postrotate,preremove endscripts' content. This is adapted from $g_localoptions_allowed_regex.
        [Regex]$scripts_content_regex = '\n[^\S\n]*\b(?:postrotate|prerotate|firstaction|lastaction|preremove)[^\n]*\n((?:.|\s)*?)\n.*\b(endscript)\b'
        $FullConfig = $scripts_content_regex.Replace($FullConfig, '')

        # Find matching bracer. If we end up without a '}', we'll throw an error
        $lines = $FullConfig.split("`n")
        $line_number = 0
        $bracer_to_find = '{'
        $bracer_left_count = 0
        $bracer_right_count = 0
        $last_bracer_line = 0
        foreach ($line in $lines) {
            $line_number++
            $level = 0
            
            [Regex]$bracers_regex = "([{}])"
            $matches = $bracers_regex.Matches($line)
            if ($matches.success) {
                 # No multiple bracers on the same line
                if ($matches.Count -gt 1) {
                    $dump = Get-LinesAround $lines $line_number | Out-String
                    throw "CONFIG: WARNING: Multiple bracers disallowed allowed at line $line_number, marked by NEAR HERE --------> : `n$dump"
                }

                $bracer_found = $matches.Groups[1].Value
                
                if ($bracer_found -ne $bracer_to_find) {
                    $problem_line = if ($bracer_to_find -eq '}') { $last_bracer_line } else { $line_number }
                    $dump = Get-LinesAround $lines $line_number | Out-String
                    throw "CONFIG: ERROR: Stay bracer '$bracer_found' at line $problem_line, marked by NEAR HERE --------> : `n$dump"
                }
                if ($bracer_found -eq '{') {
                    $bracer_left_count++
                    $bracer_to_find =  '}'
                }else {
                    $bracer_right_count++
                    $bracer_to_find =  '{'
                }

                $last_bracer_line = $line_number
            }
        }
        if ($bracer_left_count -ne $bracer_right_count) {
            $dump = Get-LinesAround $lines $line_number | Out-String
            throw "CONFIG: ERROR: Non-matching bracer found at line $line_number, near : `n$dump"
        }
    }
    function Process-Local-Block  {
        # Validates options for the block, and instantiates any Log Objects.
        [CmdletBinding()]
        param (
            # E.g. 'C:\'
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
            
            if ($g_debugFlag -band 2) { Write-Debug "[Process-Local-Block] Verbose stream: $VerbosePreference" }
            if ($g_debugFlag -band 2) { Write-Debug "[Process-Local-Block] Debug stream: $DebugPreference" } 
            if ($g_debugFlag -band 2) { Write-Debug "[Process-Local-Block] Erroraction: $ErrorActionPreference" }
            
            # $PSBoundParameters automatic variable is a hashtable containing all bound parameters (keys) and their arguments(values). These are our options.
            $options = $PSBoundParameters
            
            # Override options where overrides exist in this local block
            
            # Don't do any of the following if we defined so
            $options['compress'] = if ($nocompress) { $false } else { $compress }
            $options['copy'] = if ($nocopy) { $false } else { $copy }
            $options['copytruncate'] = if ($nocopytruncate) {$false } else { $copytruncate }
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
                                Write-Verbose "Running firstaction script"
                                if (!$g_debugFlag) {
                                    Start-Script $firstaction $blockpath -ErrorAction Stop
                                } 
                            }catch {
                                Write-Error "Failed to run firstaction script for $blockpath because $(Get-Exception-Message $_)" -ErrorAction Stop
                            }
                        }
    
                        # For sharedscripts, prerotate and postrotate scripts are run once, immediately before and after all of this block's logs are rotated.
                        # For nosharedscripts, prerotate and postrotate scripts run for each log, immediately before and after it is rotated.
                        if ($sharedscripts) {
                            # Do PrePrerotate
                            $_logsToRotate | ForEach-Object {
                                try {
                                    $log = $_
                                    $log.PrePrerotate() | Out-Null
                                }catch {
                                    Write-Error "Failed to rotate log $($log['logfile'].FullName). $(Get-Exception-Message $_)" -ErrorAction Continue
                                }
                            }
    
                            # Run any prerotate/endscript, only if using sharedscripts
                            if ( $prerotate -and ($false -notin $_logsToRotate.status.preprerotate) ) {
                                try {
                                    Write-Verbose "Running shared prerotate script"
                                    if (!$g_debugFlag) {
                                        Start-Script $prerotate $blockpath -ErrorAction Stop
                                    }
                                }catch {
                                    Write-Error "Failed to run shared prerotate script for $blockpath. $(Get-Exception-Message $_)" -ErrorAction Stop
                                }
                            }
    
                            # It's time to rotate each of these Log Objects
                            $_logsToRotate | Where-Object { $_.status.preprerotate -eq $true } | ForEach-Object {
                                try {
                                    $log = $_
                                    $log.RotateMainOnly() | Out-Null
                                }catch {
                                    Write-Error "Failed to rotate log $($log['logfile'].FullName). $(Get-Exception-Message $_)" -ErrorAction Continue
                                }
                            }
    
                            # Run any postrotate/endscript, only if using sharedscripts
                            if ( $postrotate -and ($false -notin $_logsToRotate.status.rotate) ) {
                                try {
                                    Write-Verbose "Running shared postrotate script"
                                    if (!$g_debugFlag) {
                                        Start-Script $postrotate $blockpath -ErrorAction Stop
                                    }
                                }catch {
                                    Write-Error "Failed to run shared postrotate script for $blockpath. $(Get-Exception-Message $_)" -ErrorAction Stop
                                }
                            }
    
                            # Do PostPostRotate
                            $_logsToRotate | Where-Object { $_.status.preprerotate -eq $true -and $_.status.rotate -eq $true } | ForEach-Object {
                                try {
                                    $log = $_
                                    $log.PostPostRotate() | Out-Null
                                }catch {
                                    Write-Error "Failed to rotate log $($log['logfile'].FullName). $(Get-Exception-Message $_)" -ErrorAction Continue
                                }
                            }
                        }else {
                            $_logsToRotate | ForEach-Object {
                                # For each log to rotate: move step-by-step but dont continue if a step is unsuccessful. 
                                try {
                                    $_.PrePrerotate() -and
                                    ( !$prerotate -or ($prerotate -and $_.Prerotate()) ) -and
                                    $_.RotateMainOnly() -and
                                    ( !$postrotate -or ($postrotate -and $_.Postrotate()) ) -and
                                    $_.PostPostRotate() | Out-Null
                                }catch {
                                    Write-Error $(Get-Exception-Message $_) -ErrorAction Continue
                                }
                            }
                        }
    
                        # Run any lastaction/endscript
                        if ($lastaction) { 
                            try {
                                Write-Verbose "Running lastaction script" -ErrorAction Stop
                                if (!$g_debugFlag) {
                                    Start-Script $lastaction $blockpath -ErrorAction Stop
                                }
                            }catch {
                                Write-Error "Failed to run lastaction script for $blockpath. $(Get-Exception-Message $_)" -ErrorAction Stop
                            }
                        }
                    }else {
                        if ($g_debugFlag) {
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

    try {   
        Write-Verbose "------------------------------ Log-Rotate --------------------------------------"
        Write-Verbose "Script root: $PSScriptRoot"
        if ($g_debugFlag -band 2) { Write-Verbose "Verbose stream: $VerbosePreference" }
        if ($g_debugFlag -band 2) { Write-Verbose "Debug stream: $DebugPreference" }
        if ($g_debugFlag -band 2) { Write-Debug "Erroraction: $ErrorActionPreference" }
        if ($g_debugFlag -band 2) { Write-Debug "g_debugFlag: $g_debugFlag" }
        if ($g_debugFlag -band 2) { Write-Debug "CallerEA: $CallerEA" }
        if ($g_debugFlag -band 2) { Write-Debug "ErrorActionPreference: $ErrorActionPreference" }
        
        # Get the configuration as a string
        if ($ConfigAsString) {
            # Pipelined string. Keep going
            $MultipleConfig = $ConfigAsString
        }else {
            # No pipeline string. From this point on $Config has to be a path to the config file, or directory containing config files.
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
                Write-Error "Unable to retrieve content of config $Config. $(Get-Exception-Message $_)" -ErrorAction Stop
            }
        }

        # Instantiate our BlockFactory and LogFactory
        #$BlockFactory = $BlockFactory.psobject.copy()
        #$LogFactory = $LogFactory.psobject.copy()
        #######################
        #  BlockFactory Class #
        #######################
        # BlockFactory is a stateful factory that constructs Block Objects, a Configuration. It keeps a list of Blocks.
        $BlockFactory = [PSCustomObject]@{
            'Constants' = [scriptblock]{
                # Constants
                $g_globaloptions_allowed_str = 'compress,compresscmd,uncompresscmd,compressext,compressoptions,uncompressoptions,copy,copytruncate,create,daily,dateext,dateformat,delaycompress,extension,ifempty,mail,mailfirst,maillast,maxage,minsize,missingok,monthly,nocompress,nocopy,nocopytruncate,nocreate,nodelaycompress,nodateext,nomail,nomissing,noolddir,nosharedscripts,noshred,notifempty,olddir,rotate,size,sharedscripts,shred,shredcycle,start,tabooext,weekly,yearly'
                $g_options_localonly_str = 'postrotate,prerotate,firstaction,lastaction,preremove';
                $g_options_not_switches_str = 'compresscmd,uncompresscmd,compressext,compressoptions,uncompressoptions,create,dateformat,extension,include,mail,maxage,minsize,olddir,postrotate,prerotate,firstaction,lastaction,preremove,rotate,size,shredcycle,start,tabooext'

                # Constants as arrays
                [string[]]$g_globaloptions_allowed = $g_globaloptions_allowed_str.Split(',')
                [string[]]$g_options_localonly = $g_options_localonly_str.Split(',');
                [string[]]$g_localoptions_allowed = $g_globaloptions_allowed + $g_options_localonly
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
                'size' = '1M'
                'dateformat' = '-%Y%m%d'
                'nomissingok' = $true
                'rotate' = 4
                'start' = 1
                'tabooext' = '.rpmorig, .rpmsave, .swp, .rpmnew, ~, .cfsaved, .rhn-cfg-tmp-*.'
                
                'force' = $force
            }
            'Blocks' = [ordered]@{}
            'UniqueLogFileNames' = New-Object System.Collections.ArrayList
            'PrivateHelperMethods' = [scriptblock]{
                function Get-Options {
                    param (
                        [string]$configString,
                        [hashtable]$options_found,
                        [string[]]$options_allowed,
                        [Regex]$options_allowed_regex,
                        [string[]]$options_not_switches
                    )
                    if ($g_debugFlag -band 2) { Write-Debug "[BlockFactory][Get-Options] Verbose stream: $VerbosePreference" }
                    if ($g_debugFlag -band 2) { Write-Debug "[BlockFactory][Get-Options] Debug stream: $DebugPreference" } 
                    if ($g_debugFlag -band 2) { Write-Debug "[BlockFactory][Get-Options] Erroraction: $ErrorActionPreference" }
            
                    $matches = $options_allowed_regex.Matches($configString)
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
                                                                $value.Trim() 
                                                        } else { $true }
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
                            Write-Verbose "I said $yes, I didn't say $no, although my parent said $no, I'll still go ahead."
                            $my_options.Remove($no)
                        }
                    }
                    $my_options
                }

                # Returns an array of log files, that match a given blockpath pattern but whose fullpath is not already present in a unique store
                function Get-Block-Logs {
                    param ([object]$blockObject)

                    if ($g_debugFlag -band 2) { Write-Debug "[BlockFactory][Get-Block-Logs] Verbose stream: $VerbosePreference" }
                    if ($g_debugFlag -band 2) { Write-Debug "[BlockFactory][Get-Block-Logs] Debug stream: $DebugPreference" } 
                    if ($g_debugFlag -band 2) { Write-Debug "[BlockFactory][Get-Block-Logs] Erroraction: $ErrorActionPreference" }

                    $blockpath = $blockObject['path']
                    $opt_tabooext = $blockObject['options']['tabooext']
                    $opt_missingok = if ($blockObject['options']['notmissingok']) { $false } else { $blockObject['options']['missingok'] }

                    # Split the blockpath pattern by spaces, to get either 1) log paths or 2) wildcarded-paths
                    $logpaths = [System.Collections.Arraylist]@()
                    $matches = [Regex]::Matches($blockpath, '"([^"]+)"|([^ ]+)')
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

            if ($g_debugFlag -band 2) { Write-Debug "[BlockFactory][Create] Verbose stream: $VerbosePreference" }
            if ($g_debugFlag -band 2) { Write-Debug "[BlockFactory][Create] Debug stream: $DebugPreference" } 
            if ($g_debugFlag -band 2) { Write-Debug "[BlockFactory][Create] Erroraction: $ErrorActionPreference" } 

            # Unpack my properties
            . $this.Constants

            # Unpack my methods
            . $this.PrivateHelperMethods

            # Parse Full Config for global options as hashtable
            if ($g_debugFlag -band 2) { Write-Debug "[BlockFactory][Create][Getting global options]" }
            $globalconfig = $g_localconfigs_regex.Replace($FullConfig, '')
            Get-Options $globalconfig $this.GlobalOptions $g_globaloptions_allowed $g_globaloptions_allowed_regex $g_options_not_switches    

            # Parse Full Config for all found local block(s) path pattern, options, and matching log files, storing them as hashtable. Override the global options.
            # TODO: Regex for localconfigs to match paths on multiple lines before { }
            if ($g_debugFlag -band 2) { Write-Debug "[BlockFactory][Create][Getting block options]" }
            $matches = $g_localconfigs_regex.Matches($FullConfig)
            foreach ($localconfig in $matches) {
                # A block pattern should delimit multiple paths with a space
                $my_path_pattern = ($localconfig.Groups[1].Value -Split ' ' | Where-Object { $_.Trim() }).Trim() -join " "
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
                    Write-Error "$(Get-Exception-Message($_))" -ErrorAction Continue
                }
            }
        }
        $BlockFactory | Add-Member -Name 'GetAll' -MemberType ScriptMethod -Value {
            $this.Blocks
        }

        #######################
        #   LogFactory Class   #
        #######################
        # LogFactory is a stateful factory that constructs Log Objects, and tracks their last rotation status.
        $LogFactory = [PSCustomObject]@{
            'LogObjects' = New-Object System.Collections.ArrayList
            'Status' = @{}
            'StatusFile_FullName' = "$PSScriptRoot$([IO.Path]::DirectorySeparatorChar)status"
        }
        $LogFactory | Add-Member -Name 'InitStatus' -MemberType ScriptMethod -Value {
            param ([string]$statusfile_fullname) 

            if ($g_debugFlag -band 2) { Write-Debug "[LogFactory][Create] Verbose stream: $VerbosePreference" }
            if ($g_debugFlag -band 2) { Write-Debug "[LogFactory][Create] Debug stream: $DebugPreference" } 
            if ($g_debugFlag -band 2) { Write-Debug "[LogFactory][Create] Erroraction: $ErrorActionPreference" } 

            # If no status file is specified, we'll create one in the script directory called 'status'
            if (!$statusfile_fullname) {
                $statusfile_fullname = $this.StatusFile_FullName
            }

            # Specified status file
            if ($statusfile_fullname) {
                if (Test-Path $statusfile_fullname -PathType Leaf) {
                    Write-Verbose "status file: $statusfile_fullname"

                    # Store state file fullname
                    $this.StatusFile_FullName = $statusfile_fullname
                    
                    # Read status
                    $status = Get-Content $statusfile_fullname -Raw
                }else {
                    try {
                        [io.file]::OpenWrite($statusfile_fullname).close()
                    }catch {
                        throw $_
                    }
                }
            }

            # Parse and store previous rotation status
            if ($status) {
                $status.split("`n").Trim() | Where-Object { $_ } | ForEach-Object {
                    $matches = [Regex]::Matches($_, '"([^"]+)" (.+)')
                    if ($matches.success) {
                        $path = $matches.Groups[1].Value
                        $lastRotateDate = $matches.Groups[2].Value
                        #Write-Host " --------`npath: $path`n$lastRotateDate"
                
                        if (Test-Path $path -PathType Leaf) {
                            Try {
                                $lastRotateDatetime = Get-Date -Date $lastRotateDate -Format 's' -ErrorAction SilentlyContinue
                                $this.Status[$path] = $lastRotateDatetime
                            }Catch {}
                        }
                    }
                }
            }
        }
        $LogFactory | Add-Member -Name 'Create' -MemberType ScriptMethod -Value {
            param ([System.IO.FileInfo]$logfile, [hashtable]$options)

            if ($g_debugFlag -band 2) { Write-Debug "[LogFactory][Create] Verbose stream: $VerbosePreference" }
            if ($g_debugFlag -band 2) { Write-Debug "[LogFactory][Create] Debug stream: $DebugPreference" } 
            if ($g_debugFlag -band 2) { Write-Debug "[LogFactory][Create] Erroraction: $ErrorActionPreference" } 

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

            if ($g_debugFlag -band 2) { Write-Debug "[LogFactory][DumpStatus] Verbose stream: $VerbosePreference" }
            if ($g_debugFlag -band 2) { Write-Debug "[LogFactory][DumpStatus] Debug stream: $DebugPreference" } 
            if ($g_debugFlag -band 2) { Write-Debug "[LogFactory][DumpStatus] Erroraction: $ErrorActionPreference" } 

            try {
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
                    }
                    else {
                        Write-Verbose "Not updating status of rotation for log $($_.Logfile.FullName) "
                    }
                    
                }
            
                # Dump state file
                Write-Verbose "Writing status file to $($this.StatusFile_FullName)"
                $output = "Log-Rotate state - version 1"
                $this.Status.Keys | ForEach-Object {
                    $output += "`n`"$_`" $($this.Status[$_])"
                }
                $output | Out-File $this.StatusFile_FullName -Encoding utf8    
            }catch {
                throw "Failed to write state file! Reason: $(Get-Exception-Message $_)"
            }
        }

        # Compile our Full Config
        $FullConfig = Compile-Full-Config $MultipleConfig
        
        # Validate our Full Config
        Validate-Full-Config $FullConfig

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
        if (!$g_debugFlag) {
            $LogFactory.DumpStatus()
        }
    }catch {
        Write-Error "Stopped with errors. $(Get-Exception-Message $_)" -ErrorAction $CallerEA
    }
}

# Entry point. 
# NOTE: Debug mode will not make any changes to logs. Verbose mode (Write-Verbose) is always on regardless of whether -verbose is used or not. 
Log-Rotate -Verbose -ConfigAsString $myConfig -Force -ErrorAction Stop