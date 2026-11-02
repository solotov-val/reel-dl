# reel-dl

A small Windows command-line tool that downloads Instagram reels. `reel <url>` saves the video as an
MP4 (H.264/AAC) in your Downloads folder. It works in Windows PowerShell 5.1, PowerShell 7 and cmd.

reel-dl is a thin wrapper around [yt-dlp](https://github.com/yt-dlp/yt-dlp) and
[FFmpeg](https://ffmpeg.org/). It does not scrape Instagram itself and needs no API keys or web
services.

## Features

- Reels, posts and IGTV videos (`/reel/`, `/reels/`, `/p/`, `/tv/`)
- MP4 with H.264 video and AAC audio; FFmpeg re-encodes only when Instagram delivers another codec
- Audio-only download as MP3
- Several URLs per call, or all Instagram links from the clipboard
- Tracking parameters such as `?igsh=` are removed before downloading
- Existing files are skipped, never overwritten
- Browser cookies for content that requires a login
- Console messages in German, with concrete hints for login, rate-limit and availability errors

## Requirements

- Windows 10 or 11
- [winget](https://learn.microsoft.com/windows/package-manager/winget/) (part of App Installer), used
  to install yt-dlp and FFmpeg if they are missing
- No administrator rights

## Installation

```powershell
git clone https://github.com/<user>/reel-dl.git
cd reel-dl
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Without git, download the repository as a ZIP from GitHub, extract it and run the last command in the
extracted folder.

The installer

- installs yt-dlp and FFmpeg with winget (user scope) if they are not found,
- copies `reel.ps1` to `%LOCALAPPDATA%\reel-dl` and the launcher `reel.cmd` to
  `%LOCALAPPDATA%\reel-dl\bin`,
- adds `%LOCALAPPDATA%\reel-dl\bin` to the user PATH.

Open a new terminal window afterwards so that the new PATH is picked up. In Windows Terminal, close
the whole window, not just the tab.

Your PowerShell profile is not modified. `reel.cmd` starts PowerShell with `-NoProfile` and
`-ExecutionPolicy Bypass`, so neither a slow profile nor the execution policy gets in the way.
Running `install.ps1` again updates an existing installation.

### Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

This removes `%LOCALAPPDATA%\reel-dl`, the temporary folder and the PATH entry. yt-dlp and FFmpeg
stay installed; remove them separately if you no longer need them:

```powershell
winget uninstall yt-dlp.yt-dlp
winget uninstall Gyan.FFmpeg
```

## Usage

```powershell
reel https://www.instagram.com/reel/XXXXXXXXXXX/
reel                                                # all Instagram links in the clipboard
reel https://www.instagram.com/reel/XXXXXXXXXXX/ https://www.instagram.com/p/YYYYYYYYYYY/ -Open
reel https://www.instagram.com/reel/XXXXXXXXXXX/ -Audio -OutDir D:\Music
reel https://www.instagram.com/reel/XXXXXXXXXXX/ -Cookies firefox
reel -Update
```

| Parameter | Description |
|---|---|
| `<url> ...` | One or more Instagram URLs. Without a URL, the clipboard is used. |
| `-OutDir <path>` | Target folder. Default: your Downloads folder, also if it has been moved. Created if missing. |
| `-Audio` | Save only the audio track as MP3. |
| `-Cookies <browser>` | `chrome`, `edge` or `firefox`. Uses your Instagram login from that browser. |
| `-Open` | Open the file after downloading, or the folder if several files were downloaded. |
| `-Update` | Update yt-dlp. Works with or without URLs. |

Files are named `<username>_<id>.mp4` (or `.mp3`). The full path of each file is printed at the end.

Exit codes: `0` success, `1` at least one URL failed, `2` yt-dlp or FFmpeg not found.

Full help:

```powershell
Get-Help "$env:LOCALAPPDATA\reel-dl\reel.ps1" -Full
```

## Troubleshooting

**A public reel fails to download.**
Instagram changes break yt-dlp from time to time. Run `reel -Update`. If that does not help, the
nightly build often has the fix earlier: `yt-dlp --update-to nightly`.

**Login required or rate limit.**
Use `-Cookies edge` (or `chrome`, `firefox`) and make sure you are logged in to Instagram in that
browser. Otherwise wait a few minutes and try again.

**Browser cookies cannot be read.**
Close the browser completely, including background processes. Recent versions of Chrome and Edge
encrypt their cookies in a way yt-dlp often cannot read; Firefox works more reliably.

**URLs containing `&`.**
Links copied from the Instagram website often look like `...?utm_source=ig_web_copy_link&igsh=...`.
`reel` runs through `reel.cmd`, and cmd treats `&` as a command separator. PowerShell removes your
quotes before calling `reel.cmd`, so quoting does not help there; cmd then reports an error for the
part after `&`. The download itself still works, because everything after `?` is ignored anyway. To
avoid the message, copy the link and run `reel` without arguments, or delete the part from `?` on.
In cmd itself, putting the URL in double quotes is enough.

**`reel` is not recognized.**
Open a new terminal window (close Windows Terminal completely). `$env:Path -split ';'` should list
`...\AppData\Local\reel-dl\bin`. If it does not, run `install.ps1` again.

**"Access denied" with Controlled folder access.**
If Controlled folder access is enabled in Windows Security, unknown programs cannot write to
protected folders such as Documents, Pictures or Videos. Downloads is not protected by default. If
you use `-OutDir` with a protected folder, either choose another folder or allow `yt-dlp.exe` and
`ffmpeg.exe` under *Windows Security > Virus & threat protection > Ransomware protection > Allow an
app through Controlled folder access*.

**yt-dlp or FFmpeg not found.**
`reel` looks for them on PATH and in the winget folders under `%LOCALAPPDATA%\Microsoft\WinGet`.
If they are not found, run `install.ps1` again.

## Disclaimer

Only download content you have the right to download, or for private use where the law in your
country permits it. Respect Instagram's Terms of Use and the rights of the creators. This project is
not affiliated with, endorsed or sponsored by Instagram or Meta.

## Credits

- [yt-dlp](https://github.com/yt-dlp/yt-dlp) does the actual downloading.
- [FFmpeg](https://ffmpeg.org/) merges and converts the media; the Windows builds installed by winget
  come from [gyan.dev](https://www.gyan.dev/ffmpeg/builds/).

## License

[MIT](LICENSE)
