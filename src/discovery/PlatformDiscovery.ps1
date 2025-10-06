<#
.SYNOPSIS
    Поиск платформы 1С
.DESCRIPTION
    Автоматический поиск установленной платформы 1С:Предприятие
    с поддержкой фильтрации по маске версии
.NOTES
    Проект: 1C-Sweeper
    Версия: 1.0
    Дата создания: 2025-10-06
#>

#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Импорт зависимостей
$scriptPath = if ($PSScriptRoot) { 
    $PSScriptRoot 
} elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    $PWD.Path
}

$corePath = Join-Path -Path (Split-Path -Parent $scriptPath) -ChildPath "core"
. (Join-Path -Path $corePath -ChildPath "Common.ps1")
. (Join-Path -Path $corePath -ChildPath "LoggingService.ps1")

#region Константы

# Стандартные пути установки платформы 1С
$script:StandardInstallPaths = @(
    "${env:ProgramFiles}\1cv8",
    "${env:ProgramFiles(x86)}\1cv8"
)

# Путь к реестру с информацией об установленных версиях
$script:RegistryPaths = @(
    "HKLM:\SOFTWARE\1C\1cv8",
    "HKLM:\SOFTWARE\Wow6432Node\1C\1cv8"
)

#endregion

#region Вспомогательные функции

<#
.SYNOPSIS
    Парсит строку версии в объект для удобного сравнения
.PARAMETER VersionString
    Строка версии (например, "8.3.27.1486")
.EXAMPLE
    ConvertTo-VersionObject -VersionString "8.3.27.1486"
#>
function ConvertTo-VersionObject {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VersionString
    )
    
    try {
        $parts = $VersionString -split '\.'
        
        return [PSCustomObject]@{
            Major = if ($parts.Count -gt 0) { [int]$parts[0] } else { 0 }
            Minor = if ($parts.Count -gt 1) { [int]$parts[1] } else { 0 }
            Patch = if ($parts.Count -gt 2) { [int]$parts[2] } else { 0 }
            Build = if ($parts.Count -gt 3) { [int]$parts[3] } else { 0 }
            Original = $VersionString
        }
    }
    catch {
        Write-LogWarning "Ошибка парсинга версии '$VersionString': $($_.Exception.Message)"
        return $null
    }
}

<#
.SYNOPSIS
    Сравнивает две версии
.PARAMETER Version1
    Первая версия (объект)
.PARAMETER Version2
    Вторая версия (объект)
.RETURNS
    -1 если Version1 < Version2, 0 если равны, 1 если Version1 > Version2
.EXAMPLE
    Compare-Versions -Version1 $v1 -Version2 $v2
#>
function Compare-Versions {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        $Version1,
        
        [Parameter(Mandatory = $true)]
        $Version2
    )
    
    if ($Version1.Major -ne $Version2.Major) {
        return [Math]::Sign($Version1.Major - $Version2.Major)
    }
    if ($Version1.Minor -ne $Version2.Minor) {
        return [Math]::Sign($Version1.Minor - $Version2.Minor)
    }
    if ($Version1.Patch -ne $Version2.Patch) {
        return [Math]::Sign($Version1.Patch - $Version2.Patch)
    }
    if ($Version1.Build -ne $Version2.Build) {
        return [Math]::Sign($Version1.Build - $Version2.Build)
    }
    
    return 0
}

<#
.SYNOPSIS
    Проверяет, соответствует ли версия заданной маске
.PARAMETER Version
    Объект версии
.PARAMETER Mask
    Маска версии (например, "8.3.*", "8.3.27", "8.3.2[0-9]")
.EXAMPLE
    Test-VersionMatchesMask -Version $versionObj -Mask "8.3.*"
#>
function Test-VersionMatchesMask {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        $Version,
        
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Mask
    )
    
    # Пустая маска означает "любая версия"
    if ([string]::IsNullOrWhiteSpace($Mask)) {
        return $true
    }
    
    try {
        # Преобразуем маску в regex-паттерн
        # Примеры:
        #   "8.3.*" -> "^8\.3\.\d+"
        #   "8.3.27" -> "^8\.3\.27"
        #   "8.3.2[0-9]" -> "^8\.3\.2[0-9]"
        
        $pattern = $Mask
        
        # Экранируем точки
        $pattern = $pattern.Replace('.', '\.')
        
        # Заменяем * на \d+
        $pattern = $pattern.Replace('*', '\d+')
        
        # Добавляем якоря начала и конца (частичное совпадение)
        $pattern = "^$pattern"
        
        # Проверяем соответствие
        return $Version.Original -match $pattern
    }
    catch {
        Write-LogWarning "Ошибка проверки маски '$Mask': $($_.Exception.Message)"
        return $false
    }
}

#endregion

#region Поиск платформы

<#
.SYNOPSIS
    Ищет установленные платформы в файловой системе
.EXAMPLE
    Get-InstalledPlatformsFromFS
#>
function Get-InstalledPlatformsFromFS {
    [CmdletBinding()]
    [OutputType([array])]
    param()
    
    $platforms = @()
    
    foreach ($basePath in $script:StandardInstallPaths) {
        if (-not (Test-Path -Path $basePath)) {
            continue
        }
        
        try {
            # Ищем папки с версиями (например, 8.3.27.1486)
            $versionDirs = Get-ChildItem -Path $basePath -Directory -ErrorAction SilentlyContinue |
                           Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' }
            
            foreach ($versionDir in $versionDirs) {
                # Проверяем наличие 1cv8.exe
                $exePath = Join-Path -Path $versionDir.FullName -ChildPath "bin\1cv8.exe"
                
                if (Test-Path -Path $exePath) {
                    $versionObj = ConvertTo-VersionObject -VersionString $versionDir.Name
                    
                    if ($null -ne $versionObj) {
                        $platforms += [PSCustomObject]@{
                            Version = $versionObj
                            Path = $exePath
                            Source = "FileSystem"
                        }
                    }
                }
            }
        }
        catch {
            Write-LogWarning "Ошибка поиска в '$basePath': $($_.Exception.Message)"
        }
    }
    
    return $platforms
}

<#
.SYNOPSIS
    Ищет установленные платформы в реестре Windows
.EXAMPLE
    Get-InstalledPlatformsFromRegistry
#>
function Get-InstalledPlatformsFromRegistry {
    [CmdletBinding()]
    [OutputType([array])]
    param()
    
    $platforms = @()
    
    foreach ($regPath in $script:RegistryPaths) {
        if (-not (Test-Path -Path $regPath)) {
            continue
        }
        
        try {
            # Получаем все версии из реестра
            $versionKeys = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
            
            foreach ($versionKey in $versionKeys) {
                try {
                    $installPath = (Get-ItemProperty -Path $versionKey.PSPath -Name "InstalledLocation" -ErrorAction SilentlyContinue).InstalledLocation
                    
                    if ($installPath) {
                        $exePath = Join-Path -Path $installPath -ChildPath "1cv8.exe"
                        
                        if (Test-Path -Path $exePath) {
                            $versionObj = ConvertTo-VersionObject -VersionString $versionKey.PSChildName
                            
                            if ($null -ne $versionObj) {
                                $platforms += [PSCustomObject]@{
                                    Version = $versionObj
                                    Path = $exePath
                                    Source = "Registry"
                                }
                            }
                        }
                    }
                }
                catch {
                    # Игнорируем ошибки для отдельных ключей
                    continue
                }
            }
        }
        catch {
            Write-LogWarning "Ошибка чтения реестра '$regPath': $($_.Exception.Message)"
        }
    }
    
    return $platforms
}

<#
.SYNOPSIS
    Получает список всех установленных платформ 1С
.EXAMPLE
    Get-InstalledPlatforms
#>
function Get-InstalledPlatforms {
    [CmdletBinding()]
    [OutputType([array])]
    param()
    
    Write-LogInfo "Поиск установленных платформ 1С..."
    
    # Собираем из обоих источников
    $allPlatforms = @()
    $allPlatforms += @(Get-InstalledPlatformsFromFS)
    $allPlatforms += @(Get-InstalledPlatformsFromRegistry)
    
    # Удаляем дубликаты (по версии и пути)
    $uniquePlatforms = @($allPlatforms | 
        Sort-Object -Property @{Expression={$_.Version.Original}}, Path -Unique)
    
    if (@($uniquePlatforms).Count -gt 0) {
        Write-LogSuccess "Найдено платформ: $(@($uniquePlatforms).Count)"
        
        foreach ($platform in $uniquePlatforms) {
            Write-LogInfo "  • Версия $($platform.Version.Original) ($($platform.Source))"
        }
    } else {
        Write-LogWarning "Установленные платформы 1С не найдены"
    }
    
    return $uniquePlatforms
}

<#
.SYNOPSIS
    Находит максимальную версию из списка, соответствующую маске
.PARAMETER Platforms
    Массив платформ
.PARAMETER VersionMask
    Маска версии (опционально)
.EXAMPLE
    Get-MaxMatchingPlatform -Platforms $platforms -VersionMask "8.3.27"
#>
function Get-MaxMatchingPlatform {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Platforms,
        
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$VersionMask = ""
    )
    
    if (@($Platforms).Count -eq 0) {
        return $null
    }
    
    # Фильтруем по маске
    $matchingPlatforms = @($Platforms | Where-Object {
        Test-VersionMatchesMask -Version $_.Version -Mask $VersionMask
    })
    
    if (@($matchingPlatforms).Count -eq 0) {
        Write-LogWarning "Не найдено платформ, соответствующих маске '$VersionMask'"
        return $null
    }
    
    # Находим максимальную версию
    $maxPlatform = $matchingPlatforms[0]
    
    foreach ($platform in $matchingPlatforms) {
        if ((Compare-Versions -Version1 $platform.Version -Version2 $maxPlatform.Version) -gt 0) {
            $maxPlatform = $platform
        }
    }
    
    return $maxPlatform
}

<#
.SYNOPSIS
    Находит платформу 1С для обслуживания баз
.PARAMETER VersionMask
    Маска версии (например, "8.3.27", "8.3.*"). Если пусто - берется максимальная
.EXAMPLE
    Find-Platform1C -VersionMask "8.3.*"
#>
function Find-Platform1C {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$VersionMask = ""
    )
    
    try {
        Write-LogSeparator -Title "ПОИСК ПЛАТФОРМЫ 1С"
        
        if (-not [string]::IsNullOrWhiteSpace($VersionMask)) {
            Write-LogInfo "Маска версии: $VersionMask"
        } else {
            Write-LogInfo "Маска версии не указана - будет выбрана максимальная установленная"
        }
        

        
        # Получаем все установленные платформы
        $platforms = Get-InstalledPlatforms
        
        if (@($platforms).Count -eq 0) {
            Write-LogSeparator
            return @{
                Success = $false
                Platform = $null
                Error = "Не найдено ни одной установленной платформы 1С"
            }
        }
        
        # Находим подходящую
        $selectedPlatform = Get-MaxMatchingPlatform -Platforms $platforms -VersionMask $VersionMask
        
        Write-LogSeparator
        
        if ($null -eq $selectedPlatform) {
            $errorMsg = if ([string]::IsNullOrWhiteSpace($VersionMask)) {
                "Не удалось найти платформу"
            } else {
                "Не найдено платформ, соответствующих маске '$VersionMask'"
            }
            
            Write-LogError $errorMsg
            
            return @{
                Success = $false
                Platform = $null
                Error = $errorMsg
            }
        }
        
        Write-LogSuccess "Выбрана платформа: $($selectedPlatform.Version.Original)"
        Write-LogInfo "Путь: $($selectedPlatform.Path)"
        
        return @{
            Success = $true
            Platform = $selectedPlatform
            Error = $null
        }
    }
    catch {
        $errorMsg = "Критическая ошибка поиска платформы: $($_.Exception.Message)"
        Write-LogError $errorMsg
        
        return @{
            Success = $false
            Platform = $null
            Error = $errorMsg
        }
    }
}

#endregion

# При dot-sourcing все функции автоматически доступны