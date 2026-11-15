# Installs Helmy on Windows, from its latest release on GitHub:
#   irm https://helmy.ke/install.ps1 | iex
# Runs the installer for this PC's processor (x64 or Arm), for this person alone, then
# opens Helmy.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$repo = 'https://github.com/mittolabs/helmy'

$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { 'arm64' } else { 'x64' }

# The newest release that has this build: a release just made has none until its builds
# are attached, so GitHub's "latest" can point at one with nothing to download yet. From
# the recent releases, newest first; if GitHub's API can't be read here, its "latest".
$tag = $null
try {
  $releases = Invoke-RestMethod -UseBasicParsing -Uri 'https://api.github.com/repos/mittolabs/helmy/releases?per_page=10'
  foreach ($r in $releases) {
    if ($r.draft -or $r.prerelease) { continue }
    if ($r.assets | Where-Object { $_.name -eq "Helmy-$($r.tag_name)-windows-$arch.exe" }) { $tag = $r.tag_name; break }
  }
} catch { }
if (-not $tag) {
  $latest = Invoke-WebRequest -UseBasicParsing -Uri "$repo/releases/latest" -MaximumRedirection 5
  $url = if ($latest.BaseResponse.ResponseUri) { $latest.BaseResponse.ResponseUri.AbsoluteUri } else { $latest.BaseResponse.RequestMessage.RequestUri.AbsoluteUri }
  $tag = $url -replace '.*/tag/', ''
}
if ($tag -notlike 'v*') { throw "helmy: couldn't find a release to download. See $repo/releases" }
$file = "Helmy-$tag-windows-$arch.exe"
$path = Join-Path $env:TEMP $file

Write-Host "Downloading Helmy $tag for $arch..."
Invoke-WebRequest -UseBasicParsing -Uri "$repo/releases/download/$tag/$file" -OutFile $path
Write-Host 'Installing...'
Start-Process -Wait -FilePath $path -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS'
Remove-Item $path -ErrorAction SilentlyContinue

$exe = Join-Path $env:LOCALAPPDATA 'Programs\Helmy\helmy.exe'
if (Test-Path $exe) {
  Write-Host "Helmy $tag is installed. Opening it..."
  Start-Process $exe
} else {
  throw 'helmy: the installer finished, but Helmy is not where it should be.'
}
