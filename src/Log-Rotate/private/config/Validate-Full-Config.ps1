function Validate-Full-Config {
    param ([string]$FullConfig)

    if ($g_debugFlag -band 4) { Write-Debug "[Validate-Full-Config] Verbose stream: $VerbosePreference" }
    if ($g_debugFlag -band 4) { Write-Debug "[Validate-Full-Config] Debug stream: $DebugPreference" }
    if ($g_debugFlag -band 4) { Write-Debug "[Validate-Full-Config] Erroraction: $ErrorActionPreference" }

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

    # Validate block path pattern definition. And find matching bracer.
    $lines = $FullConfig.split("`n")
    $line_number = 0
    $bracer_to_find = '{'
    $bracer_left_count = 0
    $bracer_right_count = 0
    $last_bracer_line = 0
    foreach ($line in $lines) {
        $line_number++
        $level = 0


        # Validate block definition
        [Regex]$block_path_pattern_line = "(.*)({)"
        $matches = $block_path_pattern_line.Matches($line)
        if ($matches.success) {
            # The path pattern cannot be empty
            $path_pattern = $matches.Groups[1].Value.Trim()
            if (!$path_pattern) {
                $dump = Get-LinesAround $lines $line_number | Out-String
                throw "CONFIG: WARNING: Empty path pattern disallowed allowed at line $line_number, marked by NEAR HERE --------> : `n$dump"
            }
        }

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
