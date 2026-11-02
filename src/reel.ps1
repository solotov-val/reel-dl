<#
.SYNOPSIS
    Downloads Instagram reels as MP4 or MP3.

.DESCRIPTION
    Downloads one or more Instagram reels, posts or IGTV videos with yt-dlp and saves them as
    <username>_<id>.mp4 in the Downloads folder. Videos are stored as H.264/AAC so that they play
    everywhere; other codecs are re-encoded with FFmpeg. Tracking parameters are removed from the
    URLs, and files that already exist are skipped instead of overwritten.

    Without a URL argument, all Instagram links found in the clipboard are used.

.PARAMETER Url
    One or more Instagram URLs. Accepted paths: /reel/, /reels/, /p/ and /tv/.

.PARAMETER OutDir
    Target folder. Defaults to the Downloads folder of the current user, including redirected
    locations. The folder is created if it does not exist.

.PARAMETER Audio
    Save only the audio track as MP3.

.PARAMETER Cookies
    Browser to read the Instagram session from (chrome, edge or firefox). Needed for content that
    requires a login.

.PARAMETER Open
    Open the downloaded file afterwards, or the target folder if several files were downloaded.

.PARAMETER Update
    Update yt-dlp before downloading. Can be used without a URL.

.EXAMPLE
    reel https://www.instagram.com/reel/XXXXXXXXXXX/

    Downloads a single reel to the Downloads folder.

.EXAMPLE
    reel

    Downloads all Instagram links found in the clipboard.

.EXAMPLE
    reel https://www.instagram.com/reel/XXXXXXXXXXX/ https://www.instagram.com/p/YYYYYYYYYYY/ -Open

.EXAMPLE
    reel https://www.instagram.com/reel/XXXXXXXXXXX/ -Audio -OutDir D:\Music

.EXAMPLE
    reel https://www.instagram.com/reel/XXXXXXXXXXX/ -Cookies firefox

.EXAMPLE
    reel -Update

.NOTES
    Exit codes: 0 = success, 1 = at least one URL failed, 2 = yt-dlp or FFmpeg not found.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Interactive console tool; all output is meant for the user.')]
[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Url,

    [string]$OutDir,

    [switch]$Audio,

    [ValidateSet('chrome', 'edge', 'firefox')]
    [string]$Cookies,

    [switch]$Open,

    [switch]$Update
)

# Windows PowerShell turns redirected stderr of native commands into error records. yt-dlp reports
# failures on stderr, and those must not end the script when the caller prefers 'Stop'.
$ErrorActionPreference = 'Continue'

$Messages = @{
    Error            = 'Fehler: {0}'
    MissingTools     = '{0} nicht gefunden (weder im PATH noch in den winget-Ordnern). ' +
        'Bitte install.ps1 ausführen.'
    Updating         = 'Aktualisiere yt-dlp ...'
    NoUrl            = 'Keine URL angegeben und keine Instagram-URL in der Zwischenablage.'
    FromClipboard    = 'URL aus Zwischenablage: {0}'
    InvalidUrl       = 'Ungültige URL: {0} (erwartet: instagram.com/reel/..., /reels/..., /p/... oder /tv/...)'
    Progress         = '[{0}/{1}] {2}'
    AlreadyExists    = '  Bereits vorhanden, nicht überschrieben.'
    Converting       = '  Wandle in H.264/AAC um ...'
    ConversionFailed = '  Umwandlung in H.264/AAC fehlgeschlagen; Datei bleibt im Originalformat.'
    SavedFile        = '  {0}'
    ToolOutput       = '  yt-dlp: {0}'
    Summary          = 'Fertig: {0} ok, {1} fehlgeschlagen.'
    UnknownError     = 'Unbekannter Fehler. Tipp: reel -Update, danach erneut versuchen.'
    UnknownUploader  = 'unbekannt'
}

# Checked in order against the yt-dlp error output; the first match wins.
$ErrorHints = @(
    @{
        Pattern = 'DPAPI|App-Bound|decrypt|Could not copy .*cookie|cookies database|could not find .* profile'
        Message = 'Browser-Cookies konnten nicht gelesen werden. Browser komplett schließen und erneut ' +
            'versuchen, oder -Cookies firefox verwenden (Chrome/Edge verschlüsseln Cookies inzwischen stärker).'
    }
    @{
        Pattern = 'rate-limit|429|Too Many Requests|redirected to the login page'
        Message = 'Instagram blockiert anonyme Anfragen (Rate-Limit oder Login nötig). Ein paar Minuten warten ' +
            'oder mit Login probieren: -Cookies edge (bzw. chrome/firefox; im Browser bei Instagram ' +
            'eingeloggt sein).'
    }
    @{
        Pattern = 'audio codec|no audio'
        Message = 'Dieses Reel hat keine Tonspur, daher gibt es kein MP3.'
    }
    @{
        Pattern = 'empty media response'
        Message = 'Instagram liefert nichts: Reel gelöscht/privat, Link falsch oder Login nötig. ' +
            'Probiere -Cookies edge; ist es im Browser ohne Login abspielbar: reel -Update.'
    }
    @{
        Pattern = 'login|log in|registered users|private|Restricted'
        Message = 'Dieser Inhalt braucht einen Login. Probiere: -Cookies edge (bzw. chrome/firefox; ' +
            'im Browser bei Instagram eingeloggt sein).'
    }
    @{
        Pattern = 'not available|404|Not Found|isn.t available|No video formats'
        Message = 'Inhalt nicht verfügbar (gelöscht, privat oder kein Video). Falls er im Browser ohne Login ' +
            'abspielbar ist: reel -Update ausführen und erneut versuchen.'
    }
    @{
        Pattern = 'Unable to extract|Unsupported URL|KeyError|JSON'
        Message = 'yt-dlp kommt mit der aktuellen Instagram-Seite nicht zurecht. Abhilfe meist: reel -Update'
    }
    @{
        Pattern = 'ffmpeg|ffprobe'
        Message = 'ffmpeg fehlt oder funktioniert nicht. install.ps1 erneut ausführen.'
    }
    @{
        Pattern = 'getaddrinfo|timed out|Connection|SSL|Network'
        Message = 'Netzwerkproblem. Internetverbindung prüfen und erneut versuchen.'
    }
)

function Write-Status {
    param(
        [string]$Text,
        [ConsoleColor]$Color = 'Gray'
    )
    Write-Host $Text -ForegroundColor $Color
}

function Write-Failure {
    param([string]$Text)
    Write-Host ($Messages.Error -f $Text) -ForegroundColor Red
}

function Sync-SessionPath {
    # winget writes PATH to the registry; sessions that were already open do not see the change.
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = (($env:Path, $machine, $user) -join ';') -split ';'
    $env:Path = ($entries | Where-Object { $_ } | Select-Object -Unique) -join ';'
}

function Find-Executable {
    param([string]$Name)

    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        return $command.Source
    }

    $exe = "$Name.exe"
    foreach ($dir in "$env:LOCALAPPDATA\Microsoft\WinGet\Links", "$env:ProgramFiles\WinGet\Links") {
        $candidate = Join-Path -Path $dir -ChildPath $exe
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    # Portable packages whose links were not created (or not yet) are only reachable here.
    foreach ($dir in "$env:LOCALAPPDATA\Microsoft\WinGet\Packages", "$env:ProgramFiles\WinGet\Packages") {
        if (-not (Test-Path -LiteralPath $dir)) {
            continue
        }
        $match = Get-ChildItem -LiteralPath $dir -Filter $exe -Recurse -Depth 4 -File -ErrorAction SilentlyContinue |
            Sort-Object -Property LastWriteTime -Descending |
            Select-Object -First 1
        if ($match) {
            return $match.FullName
        }
    }
    return $null
}

function Get-RequiredTool {
    $paths = [ordered]@{}
    foreach ($name in 'yt-dlp', 'ffmpeg', 'ffprobe') {
        $paths[$name] = Find-Executable -Name $name
    }
    [pscustomobject]@{
        YtDlp   = $paths['yt-dlp']
        Ffmpeg  = $paths['ffmpeg']
        Ffprobe = $paths['ffprobe']
        Missing = @($paths.Keys | Where-Object { -not $paths[$_] })
    }
}

function Get-DownloadFolder {
    # The Downloads folder can be redirected (other drive, OneDrive); $HOME\Downloads is only the default.
    $knownFolderId = '{374DE290-123F-4565-9164-39C4925E467B}'
    $shellFolders = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
    try {
        $value = (Get-ItemProperty -Path $shellFolders -Name $knownFolderId -ErrorAction Stop).$knownFolderId
        $path = [Environment]::ExpandEnvironmentVariables($value)
        if ($path -and (Test-Path -LiteralPath $path)) {
            return $path
        }
    } catch {
        Write-Verbose "Downloads folder not found in the registry: $_"
    }

    try {
        $path = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path
        if ($path -and (Test-Path -LiteralPath $path)) {
            return $path
        }
    } catch {
        Write-Verbose "Downloads folder not resolvable through the shell: $_"
    }

    Join-Path -Path $HOME -ChildPath 'Downloads'
}

function ConvertTo-ReelUrl {
    param([string]$InputUrl)

    $pattern = '^(?:https?://)?(?:www\.|m\.)?instagram\.com/(?:[A-Za-z0-9._]+/)?(reels?|p|tv)/([A-Za-z0-9_-]+)'
    if ($InputUrl.Trim() -match $pattern) {
        $kind = if ($Matches[1] -eq 'reels') { 'reel' } else { $Matches[1] }
        return [pscustomobject]@{
            Url = "https://www.instagram.com/$kind/$($Matches[2])/"
            Id  = $Matches[2]
        }
    }
    return $null
}

function Get-ClipboardUrl {
    $text = Get-Clipboard -Raw -ErrorAction SilentlyContinue
    [regex]::Matches("$text", '\S*instagram\.com/\S+') | ForEach-Object Value
}

function Get-ErrorHint {
    param([string]$ErrorText)

    foreach ($hint in $ErrorHints) {
        if ($ErrorText -match $hint.Pattern) {
            return $hint.Message
        }
    }
    return $Messages.UnknownError
}

function Get-SavedFile {
    param(
        [string]$Directory,
        [string]$Id,
        [string]$Extension
    )
    Get-ChildItem -LiteralPath $Directory -Filter "*_$Id.$Extension" -ErrorAction SilentlyContinue |
        Select-Object -First 1
}

function Get-DownloadArgument {
    param(
        [string]$Destination,
        [switch]$Audio,
        [string]$Cookies,
        [string]$FfmpegDir
    )

    # Intermediate files go to a separate temp folder, so an audio-only run can never touch an
    # existing MP4 of the same name in the destination.
    $tempDir = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath 'reel-dl'
    $arguments = @(
        '--no-playlist', '--no-overwrites', '--no-progress', '--quiet', '--no-warnings'
        '-P', "home:$Destination", '-P', "temp:$tempDir"
        '-o', "%(channel,uploader|$($Messages.UnknownUploader))s_%(id)s.%(ext)s"
    )
    if ($FfmpegDir) {
        $arguments += '--ffmpeg-location', $FfmpegDir
    }
    if ($Cookies) {
        $arguments += '--cookies-from-browser', $Cookies
    }

    if ($Audio) {
        $arguments += '-f', 'ba/b', '-x', '--audio-format', 'mp3', '--audio-quality', '0'
    } else {
        # Reels are portrait, so "better than 720p" has to be checked on the short side; the height
        # alone is already 1280 at 720p. Preference: H.264 DASH, then higher-resolution DASH in any
        # codec (re-encoded afterwards), then the progressive MP4, which Instagram serves as H.264/AAC
        # without declaring its codec.
        $selector = 'bv*[vcodec^=avc1]+ba/bv*[width>720][height>720]+ba/' +
            'b[ext=mp4][vcodec!^=?vp][vcodec!^=?av01]/bv*+ba/b'
        $arguments += '-f', $selector, '-S', 'res,fps,vcodec:h264,acodec:aac',
            '--merge-output-format', 'mp4', '--remux-video', 'mp4'
    }
    $arguments
}

function ConvertTo-CompatibleMp4 {
    param(
        [string]$Path,
        [string]$Ffmpeg,
        [string]$Ffprobe
    )

    $streams = & $Ffprobe -v error -show_entries 'stream=codec_type,codec_name' -of 'csv=p=0' $Path 2>$null
    $incompatible = $streams | Where-Object {
        ($_ -match ',video$' -and $_ -notmatch '^h264,') -or ($_ -match ',audio$' -and $_ -notmatch '^aac,')
    }
    if (-not $incompatible) {
        return $true
    }

    Write-Status $Messages.Converting
    $tempFile = [IO.Path]::ChangeExtension($Path, '.tmp.mp4')
    $ffmpegArgs = @(
        '-v', 'error', '-y', '-i', $Path
        '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '20', '-pix_fmt', 'yuv420p'
        '-c:a', 'aac', '-b:a', '160k', '-movflags', '+faststart'
        $tempFile
    )
    & $Ffmpeg @ffmpegArgs 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tempFile)) {
        Remove-Item -LiteralPath $tempFile -ErrorAction SilentlyContinue
        return $false
    }
    Move-Item -LiteralPath $tempFile -Destination $Path -Force
    return $true
}

function Write-DownloadError {
    param([string[]]$Output)

    $errorText = ($Output | Where-Object { $_ -match 'ERROR' }) -join "`n"
    if (-not $errorText) {
        $errorText = $Output -join "`n"
    }
    Write-Failure (Get-ErrorHint -ErrorText $errorText)

    $detail = ($errorText -split "`n")[0].Trim()
    if ($detail.Length -gt 160) {
        $detail = $detail.Substring(0, 157) + '...'
    }
    if ($detail) {
        Write-Status ($Messages.ToolOutput -f $detail) DarkGray
    }
}

function Invoke-ReelDownload {
    param(
        [pscustomobject]$Reel,
        [string]$Destination,
        [string]$Extension,
        [string[]]$Arguments,
        [pscustomobject]$Tools
    )

    $existing = Get-SavedFile -Directory $Destination -Id $Reel.Id -Extension $Extension
    if ($existing) {
        Write-Status $Messages.AlreadyExists Yellow
        return $existing.FullName
    }

    $output = & $Tools.YtDlp @Arguments $Reel.Url 2>&1 | ForEach-Object { "$_" }
    $exitCode = $LASTEXITCODE
    $file = Get-SavedFile -Directory $Destination -Id $Reel.Id -Extension $Extension
    if ($exitCode -ne 0 -or -not $file) {
        Write-DownloadError -Output $output
        return $null
    }

    if ($Extension -eq 'mp4') {
        $converted = ConvertTo-CompatibleMp4 -Path $file.FullName -Ffmpeg $Tools.Ffmpeg -Ffprobe $Tools.Ffprobe
        if (-not $converted) {
            Write-Status $Messages.ConversionFailed Yellow
        }
    }
    return $file.FullName
}

function Invoke-YtDlpUpdate {
    param([string]$YtDlp)

    & $YtDlp -U
    # Self-update is not possible for every package-managed install; winget can upgrade those.
    if ($LASTEXITCODE -ne 0 -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        & winget upgrade --id yt-dlp.yt-dlp -e --accept-source-agreements --accept-package-agreements
    }
}

Sync-SessionPath
$tools = Get-RequiredTool
if ($tools.Missing) {
    Write-Failure ($Messages.MissingTools -f ($tools.Missing -join ', '))
    exit 2
}

# yt-dlp looks for FFmpeg on PATH only; the winget fallback may have found it somewhere else.
$ffmpegDir = $null
if (-not (Get-Command ffmpeg -CommandType Application -ErrorAction SilentlyContinue)) {
    $ffmpegDir = Split-Path -Path $tools.Ffmpeg -Parent
}

if ($Update) {
    Write-Status $Messages.Updating Cyan
    Invoke-YtDlpUpdate -YtDlp $tools.YtDlp
    if (-not $Url) {
        exit $LASTEXITCODE
    }
}

if (-not $Url) {
    $Url = @(Get-ClipboardUrl)
    if (-not $Url) {
        Write-Failure $Messages.NoUrl
        exit 1
    }
    Write-Status ($Messages.FromClipboard -f ($Url -join ', ')) DarkGray
}

$reels = @()
$failed = 0
foreach ($entry in $Url) {
    $reel = ConvertTo-ReelUrl -InputUrl $entry
    if (-not $reel) {
        Write-Failure ($Messages.InvalidUrl -f $entry)
        $failed++
    } elseif ($reels.Id -notcontains $reel.Id) {
        $reels += $reel
    }
}
if (-not $reels) {
    exit 1
}

if (-not $OutDir) {
    $OutDir = Get-DownloadFolder
}
if (-not (Test-Path -LiteralPath $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}
$OutDir = (Resolve-Path -LiteralPath $OutDir).ProviderPath

$extension = if ($Audio) { 'mp3' } else { 'mp4' }
$arguments = Get-DownloadArgument -Destination $OutDir -Audio:$Audio -Cookies $Cookies -FfmpegDir $ffmpegDir
$saved = @()
for ($i = 0; $i -lt $reels.Count; $i++) {
    $reel = $reels[$i]
    Write-Status ($Messages.Progress -f ($i + 1), $reels.Count, $reel.Url) Cyan
    $params = @{
        Reel        = $reel
        Destination = $OutDir
        Extension   = $extension
        Arguments   = $arguments
        Tools       = $tools
    }
    $path = Invoke-ReelDownload @params
    if ($path) {
        Write-Status ($Messages.SavedFile -f $path) Green
        $saved += $path
    } else {
        $failed++
    }
}

if ($Open -and $saved) {
    $target = if ($saved.Count -eq 1) { $saved[0] } else { $OutDir }
    Invoke-Item -LiteralPath $target
}
if ($reels.Count -gt 1 -or $failed) {
    Write-Status ($Messages.Summary -f $saved.Count, $failed)
}
exit [int]($failed -gt 0)
