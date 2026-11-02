<#
.SYNOPSIS
    Installs reel-dl for the current user.

.DESCRIPTION
    Installs yt-dlp and FFmpeg with winget if they are missing, copies reel.ps1 and the reel.cmd
    launcher to %LOCALAPPDATA%\reel-dl and adds %LOCALAPPDATA%\reel-dl\bin to the user PATH.
    No administrator rights are required. Running the script again updates an existing installation.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install.ps1
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Interactive installer; all output is meant for the user.')]
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$InstallDir = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'reel-dl'
# Only bin goes on PATH; see src\reel.cmd for the reason.
$BinDir = Join-Path -Path $InstallDir -ChildPath 'bin'

$Messages = @{
    InstallingPackage = 'Installiere {0} per winget (userweit) ...'
    WingetMissing     = "winget fehlt. Bitte 'App-Installer' aus dem Microsoft Store installieren " +
        'und install.ps1 erneut ausführen.'
    DependencyError   = 'Fehler bei der Installation von yt-dlp/ffmpeg: {0}'
    ToolFound         = 'OK  {0}'
    ToolMissing       = 'FEHLT  {0}'
    ToolProblem       = '{0} nicht gefunden'
    FileCopied        = 'OK  {0} -> {1}'
    CopyError         = 'Fehler beim Kopieren nach {0}: {1}'
    CopyProblem       = 'Dateien nicht kopiert'
    PathAdded         = 'OK  User-PATH ergänzt: {0}'
    PathPresent       = 'OK  User-PATH enthält bereits {0}'
    PathError         = 'Fehler beim Eintragen in den User-PATH: {0}'
    PathProblem       = 'User-PATH nicht gesetzt'
    Incomplete        = 'Installation unvollständig: {0}.'
    RetryHint         = 'Fehler oben prüfen und install.ps1 erneut ausführen.'
    Success           = 'Installation erfolgreich.'
    NextStep          = "Neue PowerShell (oder cmd) öffnen und z. B. 'reel <Instagram-URL>' ausführen."
    TerminalHint      = 'In Windows Terminal ggf. das ganze Fenster schließen und neu öffnen, ' +
        'damit der neue PATH greift.'
}

function Write-Status {
    param(
        [string]$Text,
        [ConsoleColor]$Color = 'Gray'
    )
    Write-Host $Text -ForegroundColor $Color
}

function Sync-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = (($env:Path, $machine, $user) -join ';') -split ';'
    $env:Path = ($entries | Where-Object { $_ } | Select-Object -Unique) -join ';'
}

function Test-Executable {
    param([string]$Name)

    if (Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue) {
        return $true
    }
    $wingetDir = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\WinGet'
    if (Test-Path -LiteralPath (Join-Path -Path $wingetDir -ChildPath "Links\$Name.exe")) {
        return $true
    }
    $packageDir = Join-Path -Path $wingetDir -ChildPath 'Packages'
    $match = Get-ChildItem -LiteralPath $packageDir -Filter "$Name.exe" -Recurse -Depth 4 -File -ErrorAction Ignore |
        Select-Object -First 1
    return [bool]$match
}

function Install-WingetPackage {
    param([string]$Id)

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw $Messages.WingetMissing
    }
    Write-Status ($Messages.InstallingPackage -f $Id) Cyan
    $arguments = @(
        'install', '--id', $Id, '-e', '--disable-interactivity'
        '--accept-source-agreements', '--accept-package-agreements'
    )
    & winget @arguments --scope user
    # Packages without a user-scope installer fail with --scope user instead of falling back.
    if ($LASTEXITCODE -ne 0) {
        & winget @arguments
    }
    Sync-SessionPath
}

function Copy-ReelFile {
    param(
        [string]$SourceDir,
        [string]$InstallDir,
        [string]$BinDir
    )

    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
    $script = Join-Path -Path $InstallDir -ChildPath 'reel.ps1'
    $launcher = Join-Path -Path $BinDir -ChildPath 'reel.cmd'
    Copy-Item -LiteralPath (Join-Path -Path $SourceDir -ChildPath 'reel.ps1') -Destination $script -Force
    Copy-Item -LiteralPath (Join-Path -Path $SourceDir -ChildPath 'reel.cmd') -Destination $launcher -Force
    # Files from a downloaded ZIP carry the Mark of the Web, which RemoteSigned refuses to run.
    Unblock-File -LiteralPath $script, $launcher
}

function Get-NormalizedPath {
    param([string]$Path)
    [Environment]::ExpandEnvironmentVariables($Path).Trim().TrimEnd('\').ToLowerInvariant()
}

function Test-PathEntry {
    param(
        [string]$PathList,
        [string]$Directory
    )

    $target = Get-NormalizedPath -Path $Directory
    foreach ($entry in $PathList -split ';') {
        if ($entry.Trim() -and (Get-NormalizedPath -Path $entry) -eq $target) {
            return $true
        }
    }
    return $false
}

# PATH is read and written as the raw registry value on purpose. [Environment]::GetEnvironmentVariable
# returns it with %VARIABLES% expanded and SetEnvironmentVariable stores REG_SZ, so a round trip
# through that API would permanently flatten entries such as %USERPROFILE%\bin.
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

function Send-EnvironmentChange {
    # Without WM_SETTINGCHANGE, Explorer keeps the old PATH and new terminals would not find reel
    # until the next sign-in.
    $signature = '[DllImport("user32.dll", CharSet = CharSet.Unicode)] ' +
        'public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, ' +
        'string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);'
    try {
        if (-not ('ReelDl.NativeMethods' -as [type])) {
            Add-Type -Namespace ReelDl -Name NativeMethods -MemberDefinition $signature
        }
        $hwndBroadcast = [IntPtr]0xffff
        $wmSettingChange = 0x1A
        $smtoAbortIfHung = 2
        $result = [UIntPtr]::Zero
        [void][ReelDl.NativeMethods]::SendMessageTimeout(
            $hwndBroadcast, $wmSettingChange, [UIntPtr]::Zero, 'Environment', $smtoAbortIfHung, 5000, [ref]$result)
    } catch {
        Write-Verbose "Broadcasting the environment change failed: $_"
    }
}

function Add-UserPathEntry {
    param([string]$Directory)

    $current = Get-UserPathVariable
    if (Test-PathEntry -PathList $current -Directory $Directory) {
        return $false
    }
    $entries = @($current -split ';' | Where-Object { $_.Trim() }) + $Directory
    Save-UserPathVariable -Value ($entries -join ';')
    Send-EnvironmentChange
    return $true
}

$problems = @()

try {
    Sync-SessionPath
    if (-not (Test-Executable -Name 'yt-dlp')) {
        Install-WingetPackage -Id 'yt-dlp.yt-dlp'
    }
    if (-not (Test-Executable -Name 'ffmpeg') -or -not (Test-Executable -Name 'ffprobe')) {
        Install-WingetPackage -Id 'Gyan.FFmpeg'
    }
} catch {
    Write-Status ($Messages.DependencyError -f $_.Exception.Message) Red
}
foreach ($tool in 'yt-dlp', 'ffmpeg', 'ffprobe') {
    if (Test-Executable -Name $tool) {
        Write-Status ($Messages.ToolFound -f $tool) Green
    } else {
        Write-Status ($Messages.ToolMissing -f $tool) Red
        $problems += $Messages.ToolProblem -f $tool
    }
}

try {
    Copy-ReelFile -SourceDir (Join-Path -Path $PSScriptRoot -ChildPath 'src') -InstallDir $InstallDir -BinDir $BinDir
    Write-Status ($Messages.FileCopied -f 'reel.ps1', $InstallDir) Green
    Write-Status ($Messages.FileCopied -f 'reel.cmd', $BinDir) Green
} catch {
    Write-Status ($Messages.CopyError -f $InstallDir, $_.Exception.Message) Red
    $problems += $Messages.CopyProblem
}

try {
    if (Add-UserPathEntry -Directory $BinDir) {
        Write-Status ($Messages.PathAdded -f $BinDir) Green
    } else {
        Write-Status ($Messages.PathPresent -f $BinDir) Green
    }
    if (-not (Test-PathEntry -PathList $env:Path -Directory $BinDir)) {
        $env:Path = "$env:Path;$BinDir"
    }
} catch {
    Write-Status ($Messages.PathError -f $_.Exception.Message) Red
    $problems += $Messages.PathProblem
}

Write-Host ''
if ($problems) {
    Write-Status ($Messages.Incomplete -f ($problems -join '; ')) Red
    Write-Status $Messages.RetryHint Red
    exit 1
}
Write-Status $Messages.Success Green
Write-Status $Messages.NextStep Cyan
Write-Status $Messages.TerminalHint DarkGray
