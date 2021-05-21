Describe 'Log-Rotate' -Tag 'Integration' {

    $drive = Convert-Path 'TestDrive:\'

    $logDir = Join-Path $drive 'logs'
    $logOldDir = Join-Path $drive 'oldlogs'
    $logFile = Join-Path $logDir 'foo.log'
    $logFileContent = 'foo-bar'

    $logDir2 = Join-Path $drive 'logs2'
    $logOldDir2 = Join-Path $drive 'oldlogs2'
    $logFile2 = Join-Path $logDir2 'foo.log'
    $logFile2Content = 'foo-bar'

    $configDir = Join-Path $drive 'config'
    $configFile = Join-Path $configDir 'logrotate.conf'
    $configFileContent = @"
"$logFile" {
    rotate 3
}
"@

    $configDir2 = Join-Path $drive 'config2'
    $configFile2 = Join-Path $configDir2 'logrotate2.conf'
    $configFile2Content = @"
"$logFile" {
    rotate 3
}
"@

    $stateDir = Join-Path $drive 'state'
    $stateFile = Join-Path $stateDir 'Log-Rotate.status'

    function Init  {
        New-Item $configDir -ItemType Directory -Force > $null
        New-Item $configFile -ItemType File -Force > $null
        $configFileContent | Out-File $configFile -Encoding utf8 -Force -NoNewline

        New-Item $configDir2 -ItemType Directory -Force > $null
        New-Item $configFile2 -ItemType File -Force > $null
        $configFile2Content | Out-File $configFile2 -Encoding utf8 -Force -NoNewline

        New-Item $logDir -ItemType Directory -Force > $null
        New-Item $logOldDir -ItemType Directory -Force > $null
        New-Item $logFile -ItemType File -Force > $null
        $logFileContent | Out-File $logFile -Encoding utf8 -Force -NoNewline

        New-Item $logDir2 -ItemType Directory -Force > $null
        New-Item $logOldDir2 -ItemType Directory -Force > $null
        New-Item $logFile2 -ItemType File -Force > $null
        $logFile2Content | Out-File $logFile2 -Encoding utf8 -Force -NoNewline

        New-Item $stateDir -ItemType Directory -Force > $null
    }

    function Cleanup  {
        Get-Item $logDir -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
        Get-Item $logDir2 -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
        Get-Item $logOldDir -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
        Get-Item $logOldDir2 -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
        Get-Item $configDir -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
        Get-Item $configDir2 -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
        Get-Item $stateDir -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
    }

    Context 'Behavior from flags' {

        $eaPreference = 'Stop'

        It 'rotates a log file' {
            Init

            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference

            # Assert that the log file should be gone
            Get-Item $logFile -ErrorAction SilentlyContinue | Should -Be $null

            # Assert that the rotated log file should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 1
            $rotatedLogItems[0] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be named
            $rotatedLogItems[0].Name | Should -Be "$( Split-Path $logFile -Leaf ).1"

            Cleanup
        }

        It 'rotates a log file when forced' {
            Init

            # Rotate once
            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Recreate the log file again
            Init

            # Force another rotation
            $force = $true
            Log-Rotate -config $configFile -State $stateFile -Force:$force -ErrorAction $eaPreference 3>$null

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Assert that the rotated log file(s) should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 2
            $rotatedLogItems[0] | Should -BeOfType [System.IO.FileSystemInfo]
            $rotatedLogItems[1] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the newest rotated log file should be named
            $rotatedLogItems[0].Name | Should -Be "$( Split-Path $logFile -Leaf ).1"
            # Assert that the oldest rotated log file should be named
            $rotatedLogItems[1].Name | Should -Be "$( Split-Path $logFile -Leaf ).2"

            Cleanup
        }

        It 'does not rotate a log file in debug mode' {
            Init

            $whatif = $true
            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference -WhatIf:$whatif 3>$null 4>$null

            # Assert that the log file should not be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Not -Be $null

            Cleanup
        }

        It 'does not rotate a log file when forced in debug mode ' {
            Init

            $whatif = $true
            $force = $true
            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference -WhatIf:$whatif -Force:$force 3>$null 4>$null

            # Assert that the log file should not be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Not -Be $null

            Cleanup
        }
    }

    Context 'Behavior from configuration options' {

        $eaPreference = 'Continue'

        It "Option 'compress': rotates a log file and compresses it" {
            $configFileContent = @"
"$logFile" {
    compress
    compresscmd gzip
    compressoptions
    compressext .gz
}
"@
            Init

            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Assert that the rotated log file should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 1
            $rotatedLogItems[0] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be named
            $rotatedLogItems[0].Name | Should -Be "$( Split-Path $logFile -Leaf ).1.gz"

            Cleanup
        }

        It "Option 'compress' with 'compressoptions': rotates a log file and compresses it" {
            $configFileContent = @"
"$logFile" {
    compress
    compresscmd gzip
    compressoptions -1
    compressext .gz
}
"@
            Init

            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Assert that the rotated log file should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 1
            $rotatedLogItems[0] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be named
            $rotatedLogItems[0].Name | Should -Be "$( Split-Path $logFile -Leaf ).1.gz"

            Cleanup
        }

        It "Option 'compress' with 'compressext': rotates a log file and compresses it, renaming to a custom extension" {
            $configFileContent = @"
"$logFile" {
    compress
    compresscmd gzip
    compressoptions -1 -S .foo  # Specify a suffix for gzip
    compressext .foo
}
"@
            Init

            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Assert that the rotated log file should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 1
            $rotatedLogItems[0] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be named
            $rotatedLogItems[0].Name | Should -Be "$( Split-Path $logFile -Leaf ).1.foo"

            Cleanup
        }

        It "Option 'copy': rotates a log file as a copy" {
            $configFileContent = @"
"$logFile" {
    copy
}
"@
            Init

            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should remain
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -BeOfType [System.IO.FileSystemInfo]
            $logItem.Name | Should -Be "$( Split-Path $logFile -Leaf )"

            # Assert that the rotated log file should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 2
            $rotatedLogItems[1] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be named
            $rotatedLogItems[1].Name | Should -Be "$( Split-Path $logFile -Leaf ).1"

            # Assert that the file hashes are the same
            $logFileHash = Get-FileHash $logFile -Algorithm md5
            $rotatedLogFileHash = Get-FileHash $rotatedLogItems[0].FullName -Algorithm md5
            $logFileHash.Hash | Should -Be $rotatedLogFileHash.Hash

            Cleanup
        }

        It "Option 'copytruncate': rotates a log file as a copy and truncates the original" {
            $configFileContent = @"
"$logFile" {
    copytruncate
}
"@
            Init

            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should remain
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -BeOfType [System.IO.FileSystemInfo]
            $logItem.Name | Should -Be "$( Split-Path $logFile -Leaf )"
            $logItem.Length | Should -Be 0

            # Assert that the rotated log file should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 2
            $rotatedLogItems[1] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be named
            $rotatedLogItems[1].Name | Should -Be "$( Split-Path $logFile -Leaf ).1"

            # Assert that the file hashes are the same
            $logFileHash = Get-FileHash $logFile -Algorithm md5
            $rotatedLogFileHash = Get-FileHash $rotatedLogItems[1].FullName -Algorithm md5
            $logFileHash.Hash | Should -Not -Be $rotatedLogFileHash.Hash

            Cleanup
        }

        It "Option 'create': rotates a log file and immediately creates a new original file" {
            $configFileContent = @"
"$logFile" {
    create 700 1000 1000
}
"@
            Init

            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should remain
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -BeOfType [System.IO.FileSystemInfo]
            $logItem.Name | Should -Be "$( Split-Path $logFile -Leaf )"
            $logItem.Length | Should -Be 0

            # Assert that the rotated log file should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 2
            $rotatedLogItems[1] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be named
            $rotatedLogItems[1].Name | Should -Be "$( Split-Path $logFile -Leaf ).1"

            Cleanup
        }

        It "Option 'daily': rotates a log file only once daily" {
            $configFileContent = @"
"$logFile" {
    daily
}
"@
            Init

            # Rotate once
            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Recreate the log file again
            Init

            # Rotate again
            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should remain
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 2
            $rotatedLogItems[1] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be named
            $rotatedLogItems[1].Name | Should -Be "$( Split-Path $logFile -Leaf ).1"

            Cleanup
        }

        It "Option 'dateext': rotates a log file with a date extension" {
            $configFileContent = @"
"$logFile" {
    dateext
}
"@
            Init

            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Assert that the rotated log file should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 1
            $rotatedLogItems[0] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be named
            $rotatedLogItems[0].Name | Should -Be "$( Split-Path $logFile -Leaf )$( Get-Date -UFormat '-%Y%m%d' )"

            Cleanup
        }

        It "Option 'dateext' with 'dateformat': rotates a log file with a date extension with a custom date format" {
            $configFileContent = @"
"$logFile" {
    dateext
    dateformat -%Y%m%d
}
"@
            Init

            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Assert that the rotated log file should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 1
            $rotatedLogItems[0] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be named
            $rotatedLogItems[0].Name | Should -Be "$( Split-Path $logFile -Leaf )$( Get-Date -UFormat '-%Y%m%d' )"

            Cleanup
        }

        It "Option 'delaycompress': rotates a log file, but delays compressing the newest rotated file" {
            $configFileContent = @"
"$logFile" {
    compress
    compresscmd gzip
    compressoptions
    compressext .gz
    delaycompress
}
"@
            Init

            # Rotate once
            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Assert that the rotated log file should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 1
            $rotatedLogItems[0] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be named
            $rotatedLogItems[0].Name | Should -Be "$( Split-Path $logFile -Leaf ).1"

            # Recreate the log file again
            Init

            # Rotate another time
            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Assert that the rotated log file(s) should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 2
            $rotatedLogItems[0] | Should -BeOfType [System.IO.FileSystemInfo]
            $rotatedLogItems[1] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the newest rotated log file should be named
            $rotatedLogItems[0].Name | Should -Be "$( Split-Path $logFile -Leaf ).1"
            # Assert that the oldest rotated log file should be named
            $rotatedLogItems[1].Name | Should -Be "$( Split-Path $logFile -Leaf ).2.gz"

            Cleanup
        }

        It "Option 'firstaction': rotates a log file with a firstaction script" {
            $configFileContent = @"
"$logFile" {
    firstaction
        echo 'foo'
    endscript
}
"@
            Init

            $result = Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Assert that the rotated log file should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 1
            $rotatedLogItems[0] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be named
            $rotatedLogItems[0].Name | Should -Be "$( Split-Path $logFile -Leaf ).1"

            # Expect that the script was run
            $result | Should -Be 'foo'

            Cleanup
        }

        It "Option 'ifempty': rotates a log file even if it is empty" {
            $logFileContent = '' # empty
            $configFileContent = @"
"$logFile" {
    ifempty
}
"@
            Init

            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Assert that the rotated log file should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 1
            $rotatedLogItems[0] | Should -BeOfType [System.IO.FileSystemInfo]
            $rotatedLogItems[0].Length | Should -Be 0

            # Assert that the rotated log file should be named
            $rotatedLogItems[0].Name | Should -Be "$( Split-Path $logFile -Leaf ).1"

            Cleanup
        }

        It "Option 'include': rotates a log file, when 'include' refers to a directory" {
            $configFileContent = @"
include $configDir2
"@
            $configFile2Content = @"
"$logFile" {
    rotate 3
}
"@
            Init

            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Assert that the rotated log file should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 1
            $rotatedLogItems[0] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be named
            $rotatedLogItems[0].Name | Should -Be "$( Split-Path $logFile -Leaf ).1"

            Cleanup
        }

        It "Option 'include': rotates a log file, when 'include' refers to a file" {
            $configFileContent = @"
include $configFile2
"@
            $configFile2Content = @"
"$logFile" {
    rotate 3
}
"@
            Init

            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Assert that the rotated log file should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 1
            $rotatedLogItems[0] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be named
            $rotatedLogItems[0].Name | Should -Be "$( Split-Path $logFile -Leaf ).1"

            Cleanup
        }

        It "Option 'lastaction': rotates a log file with a lastaction script" {
            $configFileContent = @"
"$logFile" {
    lastaction
        echo 'foo'
    endscript
}
"@
            Init

            $result = Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Assert that the rotated log file should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 1
            $rotatedLogItems[0] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be named
            $rotatedLogItems[0].Name | Should -Be "$( Split-Path $logFile -Leaf ).1"

            # Expect that the script was run
            $result | Should -Be 'foo'

            Cleanup
        }

        It "Option 'missingok': rotates a log file even when other patterns don't match any log files" {
            $nonExistentLogFile = 'foo'
            $configFileContent = @"
"$nonExistentLogFile" "$logFile" {
    missingok
}
"@
            Init

            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Assert that the rotated log file should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 1
            $rotatedLogItems[0] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be named
            $rotatedLogItems[0].Name | Should -Be "$( Split-Path $logFile -Leaf ).1"

            Cleanup
        }

        It "Option 'monthly': rotates a log file only once monthly" {
            $configFileContent = @"
"$logFile" {
    monthly
}
"@
            Init

            # Rotate once
            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Recreate the log file again
            Init

            # Rotate again
            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should remain
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 2
            $rotatedLogItems[1] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be named
            $rotatedLogItems[1].Name | Should -Be "$( Split-Path $logFile -Leaf ).1"

            Cleanup
        }

        It "Option 'nocopy': rotate a log file, but not as a copy" {
            $configFileContent = @"
copy
"$logFile" {
    nocopy
}
"@
            Init

            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Assert that there should be no rotated files
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 1
            $rotatedLogItems[0] | Should -BeOfType [System.IO.FileSystemInfo]

            Cleanup
        }

        It "Option 'nocopytruncate': rotate a log file, but not as a copy to be truncated" {
            $configFileContent = @"
copytruncate
"$logFile" {
    nocopytruncate
}
"@
            Init

            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should remain
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Assert that the rotated log file should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 1
            $rotatedLogItems[0] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be named
            $rotatedLogItems[0].Name | Should -Be "$( Split-Path $logFile -Leaf ).1"

            Cleanup
        }

        It "Option 'nocreate': rotate a log file, but do not create a new a log file" {
            $configFileContent = @"
create
"$logFile" {
    nocreate
}
"@
            Init

            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Assert that there should be no rotated files
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 1
            $rotatedLogItems[0] | Should -BeOfType [System.IO.FileSystemInfo]

            Cleanup
        }

        It "Option 'nodateext': rotates a log file without a date extension" {
            $configFileContent = @"
dateext
"$logFile" {
    nodateext
}
"@
            Init

            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Assert that the rotated log file should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 1
            $rotatedLogItems[0] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be named
            $rotatedLogItems[0].Name | Should -Be "$( Split-Path $logFile -Leaf ).1"

            Cleanup
        }

        It "Option 'nodelaycompress': rotates a log file, but does not delay compressing the newest rotated file" {
            $configFileContent = @"
delaycompress
"$logFile" {
    compress
    compresscmd gzip
    compressoptions
    compressext .gz
    nodelaycompress
}
"@
            Init

            # Rotate once
            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Assert that the rotated log file should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 1
            $rotatedLogItems[0] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be named
            $rotatedLogItems[0].Name | Should -Be "$( Split-Path $logFile -Leaf ).1.gz"

            # Recreate the log file again
            Init

            # Rotate another time
            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Assert that the rotated log file(s) should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 2
            $rotatedLogItems[0] | Should -BeOfType [System.IO.FileSystemInfo]
            $rotatedLogItems[1] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the newest rotated log file should be named
            $rotatedLogItems[0].Name | Should -Be "$( Split-Path $logFile -Leaf ).1.gz"
            # Assert that the oldest rotated log file should be named
            $rotatedLogItems[1].Name | Should -Be "$( Split-Path $logFile -Leaf ).2.gz"

            Cleanup
        }

        It "Option 'nomissingok': rotate files, while issuing an error (warning) for pattern that don't match any log files" {
            $nonExistentLogFile = 'bar'
            $configFileContent = @"
missingok
"$nonExistentLogFile" "$logFile" {
    nomissingok
}
"@
            Init

            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference -ErrorVariable err #-Verbose

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Assert that the rotated log file should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 1
            $rotatedLogItems[0] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be named
            $rotatedLogItems[0].Name | Should -Be "$( Split-Path $logFile -Leaf ).1"

            Cleanup
        }

        It "Option 'noolddir': rotates a log file, but not into an olddir" {
            $configFileContent = @"
olddir $logOldDir
"$logFile" {
    noolddir
}
"@
            Init

            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Assert that the rotated log file should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 1
            $rotatedLogItems[0] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be named
            $rotatedLogItems[0].Name | Should -Be "$( Split-Path $logFile -Leaf ).1"

            Cleanup
        }

        It "Option 'nosharedscripts': rotates two log files, running a shared script only once" {
            $configFileContent = @"
sharedscripts
"$logFile" "$logFile2" {
    prerotate
        echo 'foo'
    endscript
    postrotate
        echo 'bar'
    endscript
    nosharedscripts
}
"@
            Init

            $result = Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose
            $result.Count | Should -Be 4
            $result[0] | Should -Be 'foo'
            $result[1] | Should -Be 'bar'
            $result[2] | Should -Be 'foo'
            $result[3] | Should -Be 'bar'

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Assert that the log file should be gone
            $logItem2 = Get-Item $logFile2 -ErrorAction SilentlyContinue
            $logItem2 | Should -Be $null

            # Assert that the rotated log file should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 1
            $rotatedLogItems[0] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be named
            $rotatedLogItems[0].Name | Should -Be "$( Split-Path $logFile -Leaf ).1"

            # Assert that the rotated log file should be there
            $rotatedLogItems2 = @( Get-Item $logDir2/* )
            $rotatedLogItems2.Count | Should -Be 1
            $rotatedLogItems2[0] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be named
            $rotatedLogItems2[0].Name | Should -Be "$( Split-Path $logFile2 -Leaf ).1"

            Cleanup
        }

        It "Option 'notifempty': do not rotates a log file if it is empty" {
            $logFileContent = '' # empty
            $configFileContent = @"
ifempty
"$logFile" {
    notifempty
}
"@
            Init

            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that there should be no rotated files
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 1
            $rotatedLogItems[0] | Should -BeOfType [System.IO.FileSystemInfo]
            $rotatedLogItems[0].Length | Should -Be 0

            Cleanup
        }

        It "Option 'olddir': rotates a log file into an olddir" {
            $configFileContent = @"
"$logFile" {
    olddir $logOldDir
}
"@
            Init

            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Assert that the rotated log file should be there
            $rotatedLogItems = @( Get-Item $logOldDir/* )
            $rotatedLogItems.Count | Should -Be 1
            $rotatedLogItems[0] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be named
            $rotatedLogItems[0].Name | Should -Be "$( Split-Path $logFile -Leaf ).1"

            Cleanup
        }

        It "Option 'postrotate': rotates a log file with a postrotate script" {
            $configFileContent = @"
"$logFile" {
    postrotate
        echo 'foo'
    endscript
}
"@
            Init

            $result = Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Assert that the rotated log file should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 1
            $rotatedLogItems[0] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be named
            $rotatedLogItems[0].Name | Should -Be "$( Split-Path $logFile -Leaf ).1"

            # Expect that the script was run
            $result | Should -Be 'foo'

            Cleanup
        }

        It "Option 'preremove': rotates a log file with a preremove script" {
            $configFileContent = @"
"$logFile" {
    rotate 1
    preremove
        echo 'foo'
    endscript
}
"@
            Init

            # Rotate once
            $result = Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Recreate the log file again
            Init

            # Rotate again
            $result = Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Assert that the rotated log file should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 1
            $rotatedLogItems[0] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be named
            $rotatedLogItems[0].Name | Should -Be "$( Split-Path $logFile -Leaf ).1"

            # Expect that the script was run
            $result | Should -Be 'foo'

            Cleanup
        }

        It "Option 'prerotate': rotates a log file with a prerotate script" {
            $configFileContent = @"
"$logFile" {
    prerotate
        echo 'foo'
    endscript
}
"@
            Init

            $result = Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Assert that the rotated log file should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 1
            $rotatedLogItems[0] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be named
            $rotatedLogItems[0].Name | Should -Be "$( Split-Path $logFile -Leaf ).1"

            # Expect that the script was run
            $result | Should -Be 'foo'

            Cleanup
        }

        It "Option 'rotate': rotates a log file, keeping only a certain number of old files" {
            $configFileContent = @"
"$logFile" {
    rotate 2
}
"@
            Init

            # Rotate once
            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Recreate the log file again
            Init

            # Rotate again
            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Recreate the log file again
            Init

            # Rotate again
            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Assert that the rotated log file should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 2
            $rotatedLogItems[0] | Should -BeOfType [System.IO.FileSystemInfo]
            $rotatedLogItems[1] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the newest rotated log file should be named
            $rotatedLogItems[0].Name | Should -Be "$( Split-Path $logFile -Leaf ).1"
            # Assert that the oldest rotated log file should be named
            $rotatedLogItems[1].Name | Should -Be "$( Split-Path $logFile -Leaf ).2"

            Cleanup
        }

        It "Option 'sharedscripts': rotates two log files, running a shared script only once" {
            $configFileContent = @"
"$logFile" "$logFile2" {
    sharedscripts
    prerotate
        echo 'foo'
    endscript
    postrotate
        echo 'bar'
    endscript
}
"@
            Init

            $result = Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose
            $result.Count | Should -Be 2
            $result[0] | Should -Be 'foo'
            $result[1] | Should -Be 'bar'

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Assert that the log file should be gone
            $logItem2 = Get-Item $logFile2 -ErrorAction SilentlyContinue
            $logItem2 | Should -Be $null

            # Assert that the rotated log file should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 1
            $rotatedLogItems[0] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be named
            $rotatedLogItems[0].Name | Should -Be "$( Split-Path $logFile -Leaf ).1"

            # Assert that the rotated log file should be there
            $rotatedLogItems2 = @( Get-Item $logDir2/* )
            $rotatedLogItems2.Count | Should -Be 1
            $rotatedLogItems2[0] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be named
            $rotatedLogItems2[0].Name | Should -Be "$( Split-Path $logFile2 -Leaf ).1"

            Cleanup
        }

        It "Option 'size': rotates a log file larger than specified by 'size'" {
            $configFileContent = @"
"$logFile" {
    size 1
}
"@
            Init

            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Assert that the rotated log file should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 1
            $rotatedLogItems[0] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be named
            $rotatedLogItems[0].Name | Should -Be "$( Split-Path $logFile -Leaf ).1"

            Cleanup
        }

        It "Option 'start': rotates a log file, with an numbered extension" {
            $configFileContent = @"
"$logFile" {
    start 100
}
"@
            Init

            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Assert that the rotated log file should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 1
            $rotatedLogItems[0] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be named
            $rotatedLogItems[0].Name | Should -Be "$( Split-Path $logFile -Leaf ).100"

            Cleanup
        }

        It "Option 'weekly': rotates a log file only once weekly" {
            $configFileContent = @"
"$logFile" {
    weekly
}
"@
            Init

            # Rotate once
            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Recreate the log file again
            Init

            # Rotate again
            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should remain
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 2
            $rotatedLogItems[1] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be named
            $rotatedLogItems[1].Name | Should -Be "$( Split-Path $logFile -Leaf ).1"

            Cleanup
        }

        It "Option 'yearly': rotates a log file only once yearly" {
            $configFileContent = @"
"$logFile" {
    yearly
}
"@
            Init

            # Rotate once
            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should be gone
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -Be $null

            # Recreate the log file again
            Init

            # Rotate again
            Log-Rotate -config $configFile -State $stateFile -ErrorAction $eaPreference #-Verbose

            # Assert that the log file should remain
            $logItem = Get-Item $logFile -ErrorAction SilentlyContinue
            $logItem | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be there
            $rotatedLogItems = @( Get-Item $logDir/* )
            $rotatedLogItems.Count | Should -Be 2
            $rotatedLogItems[1] | Should -BeOfType [System.IO.FileSystemInfo]

            # Assert that the rotated log file should be named
            $rotatedLogItems[1].Name | Should -Be "$( Split-Path $logFile -Leaf ).1"

            Cleanup
        }
    }
}
