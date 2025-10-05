#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptPath = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PWD.Path }
$commonPath = Join-Path -Path $scriptPath -ChildPath "Common.ps1"
if (Test-Path $commonPath) { . $commonPath }

$script:CurrentConfiguration = $null
$script:ConfigFilePath = $null

function New-ConfigurationObject {
    return [PSCustomObject]@{
        Git = [PSCustomObject]@{
            Repos = @()
            SearchPaths = @()
            SizeThresholdGB = 15.0
        }
        Edt = [PSCustomObject]@{
            Workspaces = @()
            SearchPaths = @()
            SizeThresholdGB = 5.0
        }
        Database = [PSCustomObject]@{
            Databases = @()
            SearchPaths = @()
            PlatformVersion = ""
            User = ""
            Password = ""
            SizeThresholdGB = 3.0
        }
        General = [PSCustomObject]@{
            ReportsPath = "C:\MaintenanceReports"
            SilentMode = $false
            ParallelProcessing = $false
            MaxParallelTasks = ([System.Environment]::ProcessorCount - 1)
        }
    }
}

function Get-Configuration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateScript({Test-Path -Path $_ -PathType Leaf})]
        [string]$Path,
        [Parameter(Mandatory=$false)]
        [bool]$Validate=$true
    )
    try {
        $jsonContent = Get-Content -Path $Path -Raw -Encoding UTF8
        $jsonObject = $jsonContent | ConvertFrom-Json
        $config = New-ConfigurationObject
        
        if ($jsonObject.settings.git) {
            if ($jsonObject.settings.git.repos) { $config.Git.Repos = @($jsonObject.settings.git.repos) }
            if ($jsonObject.settings.git.searchPaths) { $config.Git.SearchPaths = @($jsonObject.settings.git.searchPaths) }
            if ($null -ne $jsonObject.settings.git.sizeThresholdGB) { $config.Git.SizeThresholdGB = [double]$jsonObject.settings.git.sizeThresholdGB }
        }
        
        if ($jsonObject.settings.edt) {
            if ($jsonObject.settings.edt.workspaces) { $config.Edt.Workspaces = @($jsonObject.settings.edt.workspaces) }
            if ($jsonObject.settings.edt.searchPaths) { $config.Edt.SearchPaths = @($jsonObject.settings.edt.searchPaths) }
            if ($null -ne $jsonObject.settings.edt.sizeThresholdGB) { $config.Edt.SizeThresholdGB = [double]$jsonObject.settings.edt.sizeThresholdGB }
        }
        
        if ($jsonObject.settings.database) {
            if ($jsonObject.settings.database.databases) { $config.Database.Databases = @($jsonObject.settings.database.databases) }
            if ($jsonObject.settings.database.searchPaths) { $config.Database.SearchPaths = @($jsonObject.settings.database.searchPaths) }
            if ($jsonObject.settings.database.platformVersion) { $config.Database.PlatformVersion = $jsonObject.settings.database.platformVersion }
            if ($jsonObject.settings.database.user) { $config.Database.User = $jsonObject.settings.database.user }
            if ($jsonObject.settings.database.password) { $config.Database.Password = $jsonObject.settings.database.password }
            if ($null -ne $jsonObject.settings.database.sizeThresholdGB) { $config.Database.SizeThresholdGB = [double]$jsonObject.settings.database.sizeThresholdGB }
        }
        
        if ($jsonObject.settings.general) {
            if ($jsonObject.settings.general.reportsPath) { $config.General.ReportsPath = $jsonObject.settings.general.reportsPath }
            if ($null -ne $jsonObject.settings.general.silentMode) { $config.General.SilentMode = [bool]$jsonObject.settings.general.silentMode }
            if ($null -ne $jsonObject.settings.general.parallelProcessing) { $config.General.ParallelProcessing = [bool]$jsonObject.settings.general.parallelProcessing }
            if ($null -ne $jsonObject.settings.general.maxParallelTasks) { $config.General.MaxParallelTasks = [int]$jsonObject.settings.general.maxParallelTasks }
        }
        
        $config = Resolve-ConfigurationPaths -Config $config
        
        if ($Validate) {
            $validationResult = Test-ConfigurationValid -Config $config
            if (-not $validationResult.IsValid) { throw "Invalid config: $($validationResult.Errors -join '; ')" }
        }
        
        $script:CurrentConfiguration = $config
        $script:ConfigFilePath = $Path
        return $config
    }
    catch { throw "Error loading config: $($_.Exception.Message)" }
}

function Get-CurrentConfiguration {
    [CmdletBinding()]
    param()
    if ($null -eq $script:CurrentConfiguration) { throw "Config not loaded" }
    return $script:CurrentConfiguration
}

function Resolve-ConfigurationPaths {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Config)
    $Config.Git.Repos = @($Config.Git.Repos | ForEach-Object { Get-NormalizedPath -Path $_ })
    $Config.Git.SearchPaths = @($Config.Git.SearchPaths | ForEach-Object { Get-NormalizedPath -Path $_ })
    $Config.Edt.Workspaces = @($Config.Edt.Workspaces | ForEach-Object { Get-NormalizedPath -Path $_ })
    $Config.Edt.SearchPaths = @($Config.Edt.SearchPaths | ForEach-Object { Get-NormalizedPath -Path $_ })
    $Config.Database.Databases = @($Config.Database.Databases | ForEach-Object { Get-NormalizedPath -Path $_ })
    $Config.Database.SearchPaths = @($Config.Database.SearchPaths | ForEach-Object { Get-NormalizedPath -Path $_ })
    $Config.General.ReportsPath = Get-NormalizedPath -Path $Config.General.ReportsPath
    return $Config
}

function Test-ConfigurationValid {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Config)
    $errors = @()
    $warnings = @()
    $hasGit = ($Config.Git.Repos.Count -gt 0) -or ($Config.Git.SearchPaths.Count -gt 0)
    $hasEdt = ($Config.Edt.Workspaces.Count -gt 0) -or ($Config.Edt.SearchPaths.Count -gt 0)
    $hasDb = ($Config.Database.Databases.Count -gt 0) -or ($Config.Database.SearchPaths.Count -gt 0)
    if (-not ($hasGit -or $hasEdt -or $hasDb)) { $warnings += "No objects" }
    if ($Config.Git.SizeThresholdGB -le 0) { $errors += "Git threshold" }
    if ($Config.Edt.SizeThresholdGB -le 0) { $errors += "EDT threshold" }
    if ($Config.Database.SizeThresholdGB -le 0) { $errors += "DB threshold" }
    if ([string]::IsNullOrWhiteSpace($Config.General.ReportsPath)) { $errors += "No reports path" }
    if ($Config.General.MaxParallelTasks -lt 1) { $errors += "Parallel tasks" }
    return @{ IsValid = ($errors.Count -eq 0); Errors = $errors; Warnings = $warnings }
}

function ConvertFrom-Base64Password {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$EncodedPassword)
    if ([string]::IsNullOrEmpty($EncodedPassword)) { return "" }
    try {
        $bytes = [System.Convert]::FromBase64String($EncodedPassword)
        return [System.Text.Encoding]::UTF8.GetString($bytes)
    }
    catch { return "" }
}

function ConvertTo-Base64Password {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Password)
    if ([string]::IsNullOrEmpty($Password)) { return "" }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Password)
    return [System.Convert]::ToBase64String($bytes)
}

function New-DefaultConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)
    $config = New-ConfigurationObject
    $jsonObject = @{
        settings = @{
            git = @{ repos = @(); searchPaths = @(); sizeThresholdGB = $config.Git.SizeThresholdGB }
            edt = @{ workspaces = @(); searchPaths = @(); sizeThresholdGB = $config.Edt.SizeThresholdGB }
            database = @{ databases = @(); searchPaths = @(); platformVersion = ""; user = ""; password = ""; sizeThresholdGB = $config.Database.SizeThresholdGB }
            general = @{ reportsPath = $config.General.ReportsPath; silentMode = $config.General.SilentMode; parallelProcessing = $config.General.ParallelProcessing; maxParallelTasks = $config.General.MaxParallelTasks }
        }
    }
    $dir = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrEmpty($dir)) { Ensure-DirectoryExists -Path $dir | Out-Null }
    $jsonContent = $jsonObject | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($Path, $jsonContent, [System.Text.Encoding]::UTF8)
}

function Show-Configuration {
    [CmdletBinding()]
    param([Parameter(Mandatory=$false)]$Config=$null)
    if ($null -eq $Config) { $Config = Get-CurrentConfiguration }
    Write-Host "`n=== CONFIG ===" -ForegroundColor Cyan
    Write-Host "`n[Git]" -ForegroundColor Yellow
    Write-Host "  Repos: $($Config.Git.Repos.Count)"
    Write-Host "  Threshold: $($Config.Git.SizeThresholdGB) GB"
    Write-Host "`n[EDT]" -ForegroundColor Yellow
    Write-Host "  Workspaces: $($Config.Edt.Workspaces.Count)"
    Write-Host "  Threshold: $($Config.Edt.SizeThresholdGB) GB"
    Write-Host "`n[Database]" -ForegroundColor Yellow
    Write-Host "  Databases: $($Config.Database.Databases.Count)"
    Write-Host "  Platform: $($Config.Database.PlatformVersion)"
    Write-Host "`n[General]" -ForegroundColor Yellow
    Write-Host "  Reports: $($Config.General.ReportsPath)"
    Write-Host "  Silent: $($Config.General.SilentMode)"
    Write-Host "`n============`n" -ForegroundColor Cyan
}