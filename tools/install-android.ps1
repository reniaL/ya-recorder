# Build the current source and replace the app on the USB-connected Android phone.
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $repoRoot
try {
    & flutter build apk --debug
    if ($LASTEXITCODE -ne 0) {
        throw 'APK build failed. Installation skipped.'
    }

    # Flutter writes the configured Android SDK location during the build.
    $sdkLine = Select-String -LiteralPath 'android/local.properties' -Pattern '^sdk\.dir=' |
        Select-Object -First 1
    $sdkPath = $sdkLine.Line.Split('=', 2)[1].Replace('\\', '\').Replace('\:', ':')
    $adbPath = Join-Path $sdkPath 'platform-tools/adb.exe'

    & $adbPath -d install -r 'build/app/outputs/flutter-apk/app-debug.apk'
    if ($LASTEXITCODE -ne 0) {
        throw 'Install failed. Connect one USB Android phone, enable USB debugging, and accept the authorization prompt. See the ADB output above.'
    }

    Write-Host 'Installed. Open Yaya Recorder on your phone to test.' -ForegroundColor Green
} finally {
    Pop-Location
}
