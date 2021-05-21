function Compile-Full-Config {
    param ([string]$MultipleConfig)

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
