<#
.SYNOPSIS
    Removes reel-dl for the current user.

.DESCRIPTION
    Deletes %LOCALAPPDATA%\reel-dl and the reel-dl temp folder and removes the bin folder from the
    user PATH. yt-dlp and FFmpeg stay installed because other programs may use them. The script can
    be run any number of times.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Interactive uninstaller; all output is meant for the user.')]
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$InstallDir = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'reel-dl'
$BinDir = Join-Path -Path $InstallDir -ChildPath 'bin'
$TempDir = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath 'reel-dl'

$Messages = @{
    PathRemoved  = 'OK  Aus dem User-PATH entfernt: {0}'
    PathAbsent   = 'OK  Nicht im User-PATH: {0}'
    PathError    = 'Fehler beim Bearbeiten des User-PATH: {0}'
    Deleted      = 'OK  Gelöscht: {0}'
    NotPresent   = 'OK  Nicht vorhanden: {0}'
    DeleteError  = 'Fehler beim Löschen von {0}: {1}'
    Incomplete   = 'Deinstallation unvollständig. Fehler oben prüfen und uninstall.ps1 erneut ausführen.'
    Success      = 'reel-dl wurde entfernt.'
    Dependencies = 'yt-dlp und FFmpeg bleiben installiert. Bei Bedarf entfernen mit:'
}

function Write-Status {
    param(
        [string]$Text,
        [ConsoleColor]$Color = 'Gray'
    )
    Write-Host $Text -ForegroundColor $Color
}

function Get-NormalizedPath {
    param([string]$Path)
    [Environment]::ExpandEnvironmentVariables($Path).Trim().TrimEnd('\').ToLowerInvariant()
}

# Raw registry access keeps %VARIABLES% in the other PATH entries intact; see install.ps1.
function Get-UserPathVariable {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
    try {
        $options = [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
        return [string]$key.GetValue('Path', '', $options)
    } finally {
        if ($key) {
            $key.Close()
        }
    }
}

function Save-UserPathVariable {
    param([string]$Value)

    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    try {
        $key.SetValue('Path', $Value, [Microsoft.Win32.RegistryValueKind]::ExpandString)
    } finally {
        if ($key) {
            $key.Close()
        }
    }
}

function Remove-UserPathEntry {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Directory)

    $target = Get-NormalizedPath -Path $Directory
    $entries = @((Get-UserPathVariable) -split ';' | Where-Object { $_.Trim() })
    $remaining = @($entries | Where-Object { (Get-NormalizedPath -Path $_) -ne $target })
    if ($remaining.Count -eq $entries.Count) {
        return $false
    }
    if ($PSCmdlet.ShouldProcess('User PATH', "Remove $Directory")) {
        Save-UserPathVariable -Value ($remaining -join ';')
    }
    return $true
}

$failed = $false

try {
    if (Remove-UserPathEntry -Directory $BinDir) {
        Write-Status ($Messages.PathRemoved -f $BinDir) Green
    } else {
        Write-Status ($Messages.PathAbsent -f $BinDir) Green
    }
} catch {
    Write-Status ($Messages.PathError -f $_.Exception.Message) Red
    $failed = $true
}

foreach ($dir in $InstallDir, $TempDir) {
    if (-not (Test-Path -LiteralPath $dir)) {
        Write-Status ($Messages.NotPresent -f $dir) Green
        continue
    }
    try {
        Remove-Item -LiteralPath $dir -Recurse -Force
        Write-Status ($Messages.Deleted -f $dir) Green
    } catch {
        Write-Status ($Messages.DeleteError -f $dir, $_.Exception.Message) Red
        $failed = $true
    }
}

Write-Host ''
if ($failed) {
    Write-Status $Messages.Incomplete Red
    exit 1
}
Write-Status $Messages.Success Green
Write-Status $Messages.Dependencies DarkGray
Write-Status '  winget uninstall yt-dlp.yt-dlp' DarkGray
Write-Status '  winget uninstall Gyan.FFmpeg' DarkGray
