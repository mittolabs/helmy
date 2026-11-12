# Installs Helmy on Windows, from its latest release on GitHub:
#   irm https://helmy.ke/install.ps1 | iex
# Runs the installer for this PC's processor (x64 or Arm), for this person alone, then
# opens Helmy.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$repo = 'https://github.com/mittolabs/helmy'

# The latest release's tag, from where GitHub's "latest" link leads.
$latest = Invoke-WebRequest -UseBasicParsing -Uri "$repo/releases/latest" -MaximumRedirection 5
$url = if ($latest.BaseResponse.ResponseUri) { $latest.BaseResponse.ResponseUri.AbsoluteUri } else { $latest.BaseResponse.RequestMessage.RequestUri.AbsoluteUri }
$tag = $url -replace '.*/tag/', ''
if ($tag -notlike 'v*') { throw "helmy: couldn't find the latest release. See $repo/releases" }

$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { 'arm64' } else { 'x64' }
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
