# Log-Rotate

[![github-actions](https://github.com/theohbrothers/Log-Rotate/workflows/ci-master-pr/badge.svg)](https://github.com/theohbrothers/Log-Rotate/actions)
[![github-release](https://img.shields.io/github/v/release/theohbrothers/Log-Rotate?style=flat-square)](https://github.com/theohbrothers/Log-Rotate/releases/)
[![powershell-gallery-release](https://img.shields.io/powershellgallery/v/Log-Rotate?logo=powershell&logoColor=white&label=PSGallery&labelColor=&style=flat-square)](https://www.powershellgallery.com/packages/Log-Rotate/)

A replica of the [logrotate utility](https://github.com/logrotate/logrotate  "logrotate utility"), except this also runs on Windows systems.

It can be used as a *Powershell Script* or *Module*.

## Requirements

- <a href="https://github.com/PowerShell/PowerShell#get-powershell" target="_blank" title="Powershell">Powershell v3</a>
- `Windows`or  `*nix` environment

## The similarities

- Same command line
- Same config file format, meaning you can re-use your *nix configs
- Same rotation logic

## The differences

- **Powershell** means you can run it on  **Windows** and ***nix**
- A **Powershell module** means you can easily call it from other scripts
- A **Powershell script** means great portability and flexibility of deployment to isolated environments

## Who should use it?

- Anyone working with `Windows` and have trouble with managing tons of log files from various applications
- Anyone who works a lot in `Powershell` automation, and love the fact you can pipe configs to a *module* that runs like a *binary*.
- Those who love the option of having *portable* log rotation scripts that follow the rotation logic of `logrotate`.
- Anyone who wants to perform a *one-time rotation*, but doesn't like that `logrotate` only accepts configs as a file and not just a string.
- Anyone on `Windows` who misses that `logrotate` on `*nix`

## How to use

`Log-Rotate` can be used as a *module* or a *Task / Cron job* (as with *nix's logrotate).

### As a Module

1. [Install](https://msdn.microsoft.com/en-us/library/dd878350(v=vs.85).aspx) the `Log-Rotate.psm1` module into **any** of the following directories:

    *Windows*

    ```powershell
    %Windir%\System32\WindowsPowerShell\v1.0\Modules

    %UserProfile%\Documents\WindowsPowerShell\Modules

    %ProgramFiles%\WindowsPowerShell\Modules
    ```

    **nix*

    > Note: These may vary between *nix distros. Check `$Env:PSModulePath` inside `Powershell`.

    ```powershell
    ~/.local/share/powershell/Modules

    /usr/local/share/powershell/Modules

    /opt/microsoft/powershell/6.0.0-rc/Modules
    ```

2. Import the module, then pipe the config into the module:

    *Windows*

    ```powershell
    Import-Module Log-Rotate

    # Define your config
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

    # You can either Pipe the config
    $config | Log-Rotate -State $state -Verbose

    # Or use the full Command
    Log-Rotate -ConfigAsString $config -State $state -Verbose
    ```

    **nix*

    ```powershell
    Import-Module Log-Rotate

    # Define your config
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

    # You can either Pipe the config
    $config | Log-Rotate -State $state -Verbose

    # Or use the full Command
    Log-Rotate -ConfigAsString $config -State $state -Verbose
    ```

### As a Task / Cron job

This approach is just like how the original logrotate works. A *main config* is to `include` a folder containing *all configs*.

It requires you [install Log-Rotate as a module](#as-a-module).

#### Windows

A Main config *C:\configs\Log-Rotate\Log-Rotate.conf*, with a single `include` line :

```txt
include C:\configs\Log-Rotate.d\
```

Config files go in *C:\configs\Log-Rotate.d\\* :

```txt
C:\configs\logrotate.d\
+-- iis.conf
+-- apache.conf
+-- minecraftserver.conf
```

We'll decide to use a `Log-Rotate` *state* file in *C:\var\Log-Rotate\Log-Rotate.status*. There's no need to create it; we just have specify it on the command line for `Log-Rotate` to create and use that *state* file.

We'll decide to log the *Task* to *C:\logs\Log-Rotate.log*. This file will capture all the Powershell output streams.

Run the Command line with the `-WhatIf` parameter to make sure everything is working.

```powershell
Powershell 'Import-Module Log-Rotate; Log-Rotate -Config "C:\configs\Log-Rotate\Log-Rotate.conf" -State "C:\var\Log-Rotate\Log-Rotate.status" -Verbose -WhatIf'
```

Task Command line:

```powershell
Powershell 'Import-Module Log-Rotate; Log-Rotate -Config "C:\configs\Log-Rotate\Log-Rotate.conf" -State "C:\var\Log-Rotate\Log-Rotate.status" -Verbose' >> C:\logs\Log-Rotate.log
```

#### *nix

A Main config */etc/Log-Rotate.conf*, with a single `include` line :

```txt
include /etc/Log-Rotate.d/
```

Config files in  */etc/Log-Rotate.d/* :

```txt
/etc/Log-Rotate.d/
+-- nginx.conf
+-- apache.conf
+-- syslog.conf
```

We'll decide to use a `Log-Rotate` *state* file in */var/lib/Log-Rotate/Log-Rotate.status*. There's no need to create it; we just have specify it on the command line for `Log-Rotate` to create and use that *state* file.

We'll decide to log the *cron* to */var/log/Log-Rotate.log*. This file will capture all the Powershell output streams.

Run the Command line with the `-WhatIf` parameter to make sure everything is working.

```powershell
Powershell 'Import-Module Log-Rotate; Log-Rotate -Config "/etc/Log-Rotate.conf" -State "/var/lib/Log-Rotate/Log-Rotate.status" -Verbose -WhatIf'
```

Cron command line:

```powershell
Powershell 'Import-Module Log-Rotate; Log-Rotate -Config "/etc/Log-Rotate.conf" -State "/var/lib/Log-Rotate/Log-Rotate.status" -Verbose' >> /var/log/Log-Rotate.log
```

> Note that on certain distros, `Powershell` might be aliased as `pwsh`.

## Command Line

The command line is kept exactly the same as the original logrotate utility, while adding an additional parameter called `ConfigAsString` that accepts pipeline input.

```powershell
Log-Rotate [[-ConfigAsString] <String>] [[-Config] <String[]>] [-Force] [-Help] [[-Mail] <String>] [[-State] <String>] [-Usage] [-Version] [<CommonParameters>]

# Parameters
PARAMETERS
    -ConfigAsString <String>
        The configuration as a string, accepting input from the pipeline. Especially useful when you don't want to use a separate config file.

    -Config <String[]>
        The path to the Log-Rotate config file, or the path to a directory containing config files. If a directory is given, all files will be read as config files.
        Any number of config file paths can be given.
        Later config files will override earlier ones.
        The best method is to use a single config file that includes other config files by using the 'include' directive.

    -WhatIf [<SwitchParameter>]
        In debug mode, no logs are rotated. Use this to validate your configs or observe rotation logic.

    -Force [<SwitchParameter>]
        Forces Log-Rotate to perform a rotation for all Logs, even when Log-Rotate deems particular Log(s) to not require rotation.

    -Help [<SwitchParameter>]
        Prints Help information.

    -Mail <String>
        Tells logrotate which command to use when mailing logs.

    -State <String>
        The path to a Log-Rotate state file to use for previously rotated Logs. May be absolute or relative.
        If no state file is provided, by default the location of the state file (named 'Log-Rotate.state') will be in the calling script's directory. If there is no calling script, the location of the state file will be in the current working directory.
        If a relative path is provided, the state file path will be resolved to the current working directory.
        If a tilde ('~') is used at the beginning of the path, the state file path will be resolved to the user's home directory.

    -Usage [<SwitchParameter>]
        Prints Usage information .

    -Version [<SwitchParameter>]

    <CommonParameters>
        This cmdlet supports the common parameters: Verbose, Debug,
        ErrorAction, ErrorVariable, WarningAction, WarningVariable,
        OutBuffer, PipelineVariable, and OutVariable. For more information, see
        about_CommonParameters (https:/go.microsoft.com/fwlink/?LinkID=113216).
```

## Capturing output

Because of the pipelining nature of `Powershell`, the `stdout` is used for returning objects.

To capture streams that output the script's progress from within powershell, use `*>&1` operator :

```powershell
## Module
Log-Rotate -ConfigAsString $config -State $state -Verbose *>&1 | Out-File -FilePath ./output.log
## Script
.\Log-Rotate.ps1 *>&1 | Out-File -FilePath ./output.log
```

To capture streams that output the script's progress from outside powershell, simply redirect all `stdout` to a file:

```powershell
## Module
Powershell -Command 'Log-Rotate -ConfigAsString $config -State $state -Verbose' > output.log
## Script
Powershell -Command '.\Log-Rotate.ps1' > output.log
```

## Missing options

A few less crucial options are left out for `Log-Rotate v1`. The option and their reasons are stated below:

| Option | Explanation |
:-------:|-------------
| `mail`, `nomail` | The `mail` option isn't used very much, because the same can be achieved with greater flexibility by adding scripts to any of the following options: `firstaction`, `lastaction`, `prerotate`, `postrotate`, `preremove` .  |
| `su`    | The main reason for using `su` is to improve security and reduce chances of accidental renames, moves or deletions. Unlike *nix* systems, on Windows, SYSTEM and Adminitrator users cannot `runas` another user without entering their credentials. Unless those credentials are stored in `Credential Manager`, it is impossible for a high privileged daemon to perform rotation operations (E.g. creating, moving, copying, deleting) via an external shell. In the case that the `su` option is ever supported in the future because of the first reason, it would *only* work for `*nix` platforms. The other reason for using `su` is to preserve `ownership` and `Access Control Lists (ACLs)` on rotated files. This however, can easily be achieved by appying `ACLs` on *rotated files' container folders*, so that the any rotated files (E.g. created, moved, renamed) would immediately inherit those attributes.
| `shred`, `noshred`, `shredcycles` | This option is not supported yet, because of external dependencies on Windows - `sdelete`.

## Additional Information

### Files

When `Log-Rotate` is used as a **Script**, if the state file is unspecified on the command line, by default a `Log-Rotate` state file named *Log-Rotate.status* is created in the *script directory*.

When `Log-Rotate` is used as a **Module**, if the state file is unspecified on the command line, by default a `Log-Rotate` state file named *Log-Rotate.status* is created in the *calling script's directory* (that is, the directory of the script that executes the `Log-Rotate` command line).

### Configuration Options

The following discusses how to use certain config options.

|  Option  | Examples | Explanation |
|:--------:|----------|-------------|
| `compresscmd` | `C:\Program Files\7-Zip\7z.exe`, `C:\Program Files\7-Zip\7z`, `7z.exe`, `7z`, `gzip` | Best to use a **full path**. If using aliases, ensure the binary is among the `PATH` environment variable |
| `compressoptions` | `a -t7z`, ` ` | May be blank, in which case no parameters are sent along with`compresscmd`

## FAQ

### WinNT

Q: Help! Upon running the script I am getting an error `'File C:\...Log-Rotate.ps1 cannot be loaded because the execution of scripts is disabled on this system. Please see "get-help about_signing" for more details.'`

- You need to allow the execution of unverified scripts. Open Powershell as administrator, type `Set-ExecutionPolicy Unrestricted -Force` and press ENTER. Try running the script again. You can easily restore the security setting back by using `Set-ExecutionPolicy Undefined -Force`.

Q: Help! Upon running the script I am getting an error `File C:\...Log-Rotate.ps1 cannot be loaded. The file C:\...\Log-Rotate.ps1 is not digitally signed. You cannot run this script on the current system. For more information about running scripts and setting execution policy, see about_Execution_Policies at http://go.microsoft.com/fwlink/?LinkID=135170.`

- You need to allow the execution of unverified scripts. Open Powershell as administrator, type `Set-ExecutionPolicy Unrestricted -Force` and press ENTER. Try running the script again. You can easily restore the security setting back by using `Set-ExecutionPolicy Undefined -Force`.

Q: Help! Upon running the script I am getting a warning `'Execution Policy change. The execution policy helps protect you from scripts that you do not trust. Changing the execution policy might expose you to the security risks described in the about_Execution_Policies help topic at http://go.microsoft.com/?LinkID=135170. Do you want to change the execution policy?`

- You need to allow the execution of unverified scripts. Type `Y` for yes and press enter. You can easily restore the security setting back opening Powershell as administrator, and using the code `Set-ExecutionPolicy Undefined -Force`.

### *nix

Q: Help! I am getting an error `Powershell: command not found`.

- `Powershell` is sometimes aliased as `pwsh`, depending on which *nix distro you are on. Try the alias `pwsh`.

## Known issues

- Nil

## Background

`Log-Rotate` is replicated from the original [logrotate utility](https://github.com/logrotate/logrotate "logrotate utility"). The code was written by hand and no code was referred to.
It is made to work in the exact way logrotate would work: Same rotation logic, same outputs, same configurations. But with much more flexibility.
Best of all, it works on one more platform: **Windows**.
