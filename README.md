# Log-Rotate

A replica of the [logrotate utility](https://github.com/logrotate/logrotate  "logrotate utility"), except this also runs on Windows systems.

It can be used as a *Powershell Script* or *Module*.

## Requirements:
- <a href="https://github.com/PowerShell/PowerShell#get-powershell" target="_blank" title="Powershell">Powershell v3</a>
- `Windows`or  `*nix` environment
- User with `read` `write` `modify` (or `rwx`) permissions on script directory

## The similarities
- Same command line
- Same config file format, meaning you can re-use your *nix configs
- Same rotation logic

## The differences
- **Powershell** means you can run it on  **Windows** and ***nix**
- A **Powershell module** means you can easily call it from other scripts
- A **Powershell script** means great portability and flexibility of deployment to isolated environments

## Who should use it?
- Anyone working on Windows
- Anyone who works a lot in Powershell automation, and love the fact you can pipe configs a module

## How to use
#### Run as a script
1. Open `Log-Rotate.ps1` in your favourite text editor and add your configuration inside `$myConfig`:
```powershell
$myConfig = @'
##### Start adding Config here #####
# Global options
size 1M

# Block options
"C:\inetpub\logs\iis\mylogs\*.log" D:\console.log {
    rotate 365
    dateext
    ...
}
##### End adding #####
@'
```
2. Run the script:
- WinNT: Right click on the script in explorer and select <code>Run with Powershell</code>. (should be present on Windows 7 and up). Alternatively, open command prompt in the script directory, and run <code>Powershell .\site-scraper-warmer.ps1</code>
- *nix: Run <code>powershell ./site-scraper-warmer.ps1</code> or <code>pwsh ./site-scraper-warmer.ps1</code> depending on which version of powershell you're running.

#### Run as a module
1. [Install the module](https://msdn.microsoft.com/en-us/library/dd878350(v=vs.85).aspx) into **any** of the following: 
```powershell
`%Windir%\System32\WindowsPowerShell\v1.0\Modules`

`%UserProfile%\Documents\WindowsPowerShell\Modules`

`%ProgramFiles%\WindowsPowerShell\Modules`
```

2. Import the module, then pipe the config into the module:
```powershell
Import-Module Log-Rotate

# Define your config
$config = @'
"/var/log/httpd/access.log" {
    rotate 365
    size 10M
    postrotate
        /usr/bin/killall -HUP httpd
    endscript
}
'@

# You can either Pipe the config
$config | Log-Rotate -Verbose 

# Or use the full Command
Log-Rotate -ConfigAsString $config -Verbose 
```

### Command Line
The command line is kept exactly the same as the original logrotate utility, while adding an additional parameter called `ConfigAsString` that accepts piped input.
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
    
    -Debug [<SwitchParameter>]
        In debug mode, no logs are rotated. Use this to validate your configs or observe rotation logic.

    -Force [<SwitchParameter>]
        Forces Log-Rotate to perform a rotation for all Logs, even when Log-Rotate deems particular Log(s) to not require rotation.

    -Help [<SwitchParameter>]
        Prints Help information.

    -Mail <String>
        Tells logrotate which command to use when mailing logs.

    -State <String>
        The full path to a Log-Rotate state file to use for previously rotated Logs. The default location of the state file is within Log-Rotate's containing directory.

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
Because of the piping nature of `Powershell`, the `stdout` is used for returning objects. To capture streams that output the script's progress, capture them with `*>&1` operator:
```powershell
# If using as a module
Log-Rotate -ConfigAsString $myConfig -Verbose *>&1 | Out-File -FilePath ./output.log

# If using as a script
Powershell .\Log-Rotate.ps1 *>&1 > output.txt
```
## Missing options
A few less crucial options are left out for `Log-Rotate V1`. The option and their reasons are stated below:

| Option | Explanation |
:-------:|-------------
| `mail`, `nomail` | The `mail` option isn't used very much, because the same can be achieved with greater flexibility by adding scripts to any of the following options: `firstaction`, `lastaction`, `prerotate`, `postrotate`, `preremove` .  | 
| `su`    | The main reason for using `su` is to improve security and reduce chances of accidental renames, moves or deletions. Unlike *nix* systems, on Windows, SYSTEM and Adminitrator users cannot `runas` another user without entering their credentials. Unless those credentials are stored in `Credential Manager`, it is impossible for a high privileged daemon to perform rotation operations (E.g. creating, moving, copying, deleting) via an external shell. In the case that the `su` option is ever supported in future because of the first reason, it would *only* work for `*nix` platforms. The other reason is to preserve `ownership` and `Access Control Lists (ACLs)` on rotated files. This however, can easily be achieved by appying `ACLs` on *rotated files' container folders*, so that the any rotated files (E.g. created, moved, renamed) would immediately inherit those attributes.
| `shred`, `noshred`, `shredcycles` | This option is not supported yet, because of external dependencies on Windows - `sdelete`. 


## FAQ 
### WinNT
Q: Help! I am getting an error <code>'File C:\...Log-Rotate.ps1 cannot be loaded because the execution of scripts is disabled on this system. Please see "get-help about_signing" for more details.'</code>
- You need to allow the execution of unverified scripts. Open Powershell as administrator, type <code>Set-ExecutionPolicy Unrestricted -Force</code> and press ENTER. Try running the script again. You can easily restore the security setting back by using <code>Set-ExecutionPolicy Undefined -Force</code>.

Q: Help! Upon running the script I am getting a warning <code>'Execution Policy change. The execution policy helps protect you from scripts that you do not trust. Changing the execution policy might expose you to the security risks described in the about_Execution_Policies help topic at http://go.microsoft.com/?LinkID=135170. Do you want to change the execution policy?</code>
- You need to allow the execution of unverified scripts. Type <code>Y</code> for yes and press enter. You can easily restore the security setting back opening Powershell as administrator, and using the code <code>Set-ExecutionPolicy Undefined -Force</code>.

### *nix
Nil

## Known issues
Nil

## Background
`Log-Rotate` is replicated from the original [logrotate utility](https://github.com/logrotate/logrotate "logrotate utility"). The code was written by hand and no code was referred to.
It is made to work in the exact way logrotate would work: Same rotation logic, same outputs, same configurations. 
Best of all, it works on one more platform: **Windows**. 