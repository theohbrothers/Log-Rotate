# - Initial setup: Fill in the GUID value. Generate one by running the command 'New-GUID'. Then fill in all relevant details.
# - Ensure all relevant details are updated prior to publishing each version of the module.
# - To simulate generation of the manifest based on this definition, run the included development entrypoint script Invoke-PSModulePublisher.ps1.
# - To publish the module, tag the associated commit and push the tag.
@{
    RootModule = 'Log-Rotate.psm1'
    # ModuleVersion = ''                            # Value will be set for each publication based on the tag ref. Defaults to '0.0.0' in development environments and regular CI builds
    GUID = '44347384-7b42-439e-b835-f8bdcfe0c33c'
    Author = 'The Oh Brothers'
    CompanyName = 'The Oh Brothers'
    Copyright = '(c) 2017 The Oh Brothers'
    Description = 'A replica of the logrotate utility, except this also runs on Windows systems.'
    PowerShellVersion = '3.0'
    # PowerShellHostName = ''
    # PowerShellHostVersion = ''
    # DotNetFrameworkVersion = ''
    # CLRVersion = ''
    # ProcessorArchitecture = ''
    # RequiredModules = @()
    # RequiredAssemblies = @()
    # ScriptsToProcess = @()
    # TypesToProcess = @()
    # FormatsToProcess = @()
    # NestedModules = @()
    FunctionsToExport = @()
    CmdletsToExport = @(
        'Log-Rotate'
    )
    VariablesToExport = @()
    AliasesToExport = @()
    # DscResourcesToExport = @()
    # ModuleList = @()
    # FileList = @()
    PrivateData = @{
        # PSData = @{           # Properties within PSData will be correctly added to the manifest via Update-ModuleManifest without the PSData key. Leave the key commented out.
            Tags = @(
                'pwsh',
                'powershell',
                'module'
                'logrotate',
                'log',
                'log-administration',
                'log-management',
                'log-rotation',
                'logs'
            )
            LicenseUri = 'https://raw.githubusercontent.com/theohbrothers/Log-Rotate/master/LICENSE'
            ProjectUri = 'https://github.com/theohbrothers/Log-Rotate'
            # IconUri = ''
            # ReleaseNotes = ''
            # Prerelease = ''
            # RequireLicenseAcceptance = $false
            # ExternalModuleDependencies = @()
        # }
        # HelpInfoURI = ''
        # DefaultCommandPrefix = ''
    }
}
