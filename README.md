# Log-Rotate

[![github-actions](https://github.com/theohbrothers/Log-Rotate/actions/workflows/ci-master-pr.yml/badge.svg?branch=master)](https://github.com/theohbrothers/Log-Rotate/actions/workflows/ci-master-pr.yml)
[![github-release](https://img.shields.io/github/v/release/theohbrothers/Log-Rotate?style=flat-square)](https://github.com/theohbrothers/Log-Rotate/releases/)
[![powershell-gallery-release](https://img.shields.io/powershellgallery/v/Log-Rotate?logo=powershell&logoColor=white&label=PSGallery&labelColor=&style=flat-square)](https://www.powershellgallery.com/packages/Log-Rotate/)

A replica of the [logrotate utility](https://github.com/logrotate/logrotate "logrotate utility"), except this also runs on Windows systems.

## Install

Open [`powershell`](https://docs.microsoft.com/en-us/powershell/scripting/windows-powershell/install/installing-windows-powershell?view=powershell-5.1) or [`pwsh`](https://github.com/powershell/powershell#-powershell) and type:

```powershell
Install-Module -Name Log-Rotate -Repository PSGallery -Scope CurrentUser -Verbose
```

If prompted to trust the repository, hit `Y` and `enter`.

## Log-Rotate vs `logrotate`

Log-Rotate is an independent port of `logrotate`. It's made to work exactly the same way as the original `logrotate`, except it works in Powershell and especially Windows.

- Same command line
- Same config file format, meaning you can re-use your `*nix` configs
- Same rotation logic
- Runs on Powershell or Powershell core.

Who should use it?

- Anyone with a `Windows` environment where `docker` is unavailable
- Anyone who misses that `logrotate` on `*nix`
- Anyone working with `Windows` and have trouble with managing tons of log files from various applications
- Anyone who works a lot in `Powershell` automation, and love the fact you can pipe configs into a module.
- Anyone who wants to perform a *one-time rotation*, but doesn't like that `logrotate` only accepts configs as a file and not just a string.

## Usage

### Windows

```powershell
Import-Module Log-Rotate

# Define your config
# Double-quotes necessary only if there are spaces in the path
$config = @'
"C:\inetpub\logs\access.log" {
    rotate 365
    size 10M
    postrotate
        # My shell is powershell
        Write-Host "Rotated $( $Args[1] )"
    endscript
}
'@

# Decide on a Log-Rotate state file that will be created by Log-Rotate
$state = 'C:\var\Log-Rotate\Log-Rotate.status'

# To check rotation logic without rotating files, use the -WhatIf switch (implies -Verbose)
$config | Log-Rotate -State $state -WhatIf

# You can either Pipe the config
$config | Log-Rotate -State $state -Verbose

# Or use the full Command
Log-Rotate -ConfigAsString $config -State $state -Verbose
```

### *nix

```powershell
Import-Module Log-Rotate

# Define your config
# Double-quotes necessary only if there are spaces in the path
$config = @'
"/var/log/httpd/access.log" {
    rotate 365
    size 10M
    postrotate
        # My shell is sh
        /usr/bin/killall -HUP httpd
        echo "Rotated ${1}"
    endscript
}
'@

# Decide on a Log-Rotate state file that will be created by Log-Rotate
$state = '/var/lib/Log-Rotate/Log-Rotate.status'

# To check rotation logic without rotating files, use the -WhatIf switch (implies -Verbose)
$config | Log-Rotate -State $state -WhatIf

# You can either Pipe the config
$config | Log-Rotate -State $state -Verbose

# Or use the full Command
Log-Rotate -ConfigAsString $config -State $state -Verbose
```

## Usage as a Scheduled Task or Cron job

### Windows Scheduled Task

A main config `C:\configs\Log-Rotate\Log-Rotate.conf`:

```txt
include C:\configs\Log-Rotate.d\
```

Config files in `C:\configs\Log-Rotate.d\`:

```txt
C:\configs\logrotate.d\
+-- iis.conf
+-- apache.conf
+-- minecraftserver.conf
```

Decide on a state file `C:\var\Log-Rotate\Log-Rotate.status`.

Run the command with `-WhatIf` to simulate the rotation, making sure everything is working.

```powershell
Import-Module Log-Rotate; Log-Rotate -Config C:\configs\Log-Rotate\Log-Rotate.conf -State C:\var\Log-Rotate\Log-Rotate.status -Verbose -WhatIf
```

Decide on a log file  `C:\logs\Log-Rotate.log`.

Scheduled Task Command line:

```powershell
# Powershell
powershell -Command 'Import-Module Log-Rotate; Log-Rotate -Config C:\configs\Log-Rotate\Log-Rotate.conf -State C:\var\Log-Rotate\Log-Rotate.status -Verbose' >> C:\logs\Log-Rotate.log
# pwsh
pwsh -Command 'Import-Module Log-Rotate; Log-Rotate -Config C:\configs\Log-Rotate\Log-Rotate.conf -State C:\var\Log-Rotate\Log-Rotate.status -Verbose' >> C:\logs\Log-Rotate.log
```

#### *nix cron

A Main config `/etc/Log-Rotate.conf`, with a single `include` line :

```txt
include /etc/Log-Rotate.d/
```

Config files in `/etc/Log-Rotate.d/`:

```txt
/etc/Log-Rotate.d/
+-- nginx.conf
+-- apache.conf
+-- syslog.conf
```

Decide on a state file `/var/lib/Log-Rotate/Log-Rotate.status`.

Run the command with `-WhatIf` to simulate the rotation, making sure everything is working.

```powershell
pwsh -Command 'Import-Module Log-Rotate; Log-Rotate -Config /etc/Log-Rotate.conf -State /var/lib/Log-Rotate/Log-Rotate.status -Verbose -WhatIf'
```

Decide on a log file `/var/log/Log-Rotate.log`.

Cron command line:

```powershell
pwsh -Command 'Import-Module Log-Rotate; Log-Rotate -Config /etc/Log-Rotate.conf -State /var/lib/Log-Rotate/Log-Rotate.status -Verbose' >> /var/log/Log-Rotate.log
```

## Configuration

### State

If `-State` is unspecified, by default a `Log-Rotate.status` state file is created in the working directory.

### Configuration Options

The following discusses how to use certain config options.

|  Option  | Examples | Explanation |
|:--------:|----------|-------------|
| `compresscmd` | `C:\Program Files\7-Zip\7z.exe`, `C:\Program Files\7-Zip\7z`, `7z.exe`, `7z`, `gzip` | Best to use a **full path**. If using aliases, ensure the binary is among the `PATH` environment variable |
| `compressoptions` | `a -t7z`, ` ` | May be blank, in which case no parameters are sent along with`compresscmd`

### Missing options

A few less crucial options are left out for `Log-Rotate v1`. The option and their reasons are stated below:

| Option | Explanation |
:-------:|-------------
| `mail`, `nomail` | The `mail` option isn't used very much, because the same can be achieved with greater flexibility by adding scripts to any of the following options: `firstaction`, `lastaction`, `prerotate`, `postrotate`, `preremove` .  |
| `su`    | The main reason for using `su` is to improve security and reduce chances of accidental renames, moves or deletions. Unlike *nix* systems, on Windows, SYSTEM and Adminitrator users cannot `runas` another user without entering their credentials. Unless those credentials are stored in `Credential Manager`, it is impossible for a high privileged daemon to perform rotation operations (E.g. creating, moving, copying, deleting) via an external shell. In the case that the `su` option is ever supported in the future because of the first reason, it would *only* work for `*nix` platforms. The other reason for using `su` is to preserve `ownership` and `Access Control Lists (ACLs)` on rotated files. This however, can easily be achieved by appying `ACLs` on *rotated files' container folders*, so that the any rotated files (E.g. created, moved, renamed) would immediately inherit those attributes.
| `shred`, `noshred`, `shredcycles` | This option is not supported yet, because of external dependencies on Windows - `sdelete`.
| `minage`    | unknown reason.
