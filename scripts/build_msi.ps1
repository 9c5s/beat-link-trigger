#Requires -Version 7.3
# fork 版の beat-link と BLT をビルドし、Windows 用のインストーラーを target\ に作る
# 使い方: pwsh scripts\build_msi.ps1（beat-link は BLT と同じ親ディレクトリに clone しておく）

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$bltDir = Split-Path -Parent $PSScriptRoot
$beatLinkDir = $env:BEAT_LINK_DIR ?? (Join-Path (Split-Path -Parent $bltDir) 'beat-link')
$wixDir = $env:WIX_DIR ?? "$env:USERPROFILE\.local\opt\wix314"

if (-not (Test-Path "$env:JAVA_HOME\bin\jpackage.exe")) {
    throw "JAVA_HOME に jpackage がありません。JDK 21 以上を指定してください: $env:JAVA_HOME"
}
if (-not (Test-Path "$wixDir\candle.exe")) {
    throw "WiX 3 が見つかりません。WIX_DIR で場所を指定してください: $wixDir"
}
$env:Path = "$env:JAVA_HOME\bin;$env:Path"

# IPv6 で外部に接続できない環境でも依存ライブラリと文書の UI を取得できるようにする
$env:MAVEN_OPTS = '-Djava.net.preferIPv4Stack=true'
$env:LEIN_JVM_OPTS = '-Djava.net.preferIPv4Stack=true'
$env:NODE_OPTIONS = '--dns-result-order=ipv4first'

$appName = 'Beat Link Trigger'
$resources = Join-Path $bltDir '.github\resources'
$work = Join-Path $bltDir 'target\msi'

Push-Location
try {
    Write-Host 'beat-link をビルドしています。'
    Set-Location $beatLinkDir
    mvn.cmd -q '-Dgpg.skip' '-Dmaven.javadoc.skip=true' clean install

    Write-Host 'BLT をビルドしています。'
    Set-Location $bltDir
    npm install --no-fund --no-audit
    lein.bat uberjar

    $version = [regex]::Match((Get-Content resources\beat_link_trigger\version.edn -Raw), ':version "([^"]+)"').Groups[1].Value
    # jpackage と MSI は数字だけのバージョンしか受け付けない
    $appVersion = $version.Split('-')[0]

    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force "$work\input" | Out-Null
    Copy-Item target\beat-link-trigger.jar "$work\input\"

    Write-Host 'アプリケーションを作成しています。'
    jpackage --name $appName --input "$work\input" --dest $work --type app-image `
        --add-modules 'java.base,java.desktop,java.management,java.naming,java.prefs,java.sql,jdk.javadoc,jdk.zipfs,jdk.unsupported' `
        --java-options '-Djava.net.preferIPv4Stack=true -XX:+UseZGC' `
        --icon "$resources\BeatLink.ico" --main-jar beat-link-trigger.jar `
        --description 'Trigger events and automate shows in response to events on Pioneer CDJs' `
        --copyright '© 2016-2024 Deep Symmetry, LLC' --vendor 'Deep Symmetry, LLC' `
        --app-version $appVersion

    Write-Host 'インストーラーを作成しています。'
    Set-Location $work
    # テンプレートはリポジトリ直下から実行する前提の相対パスで資源を参照している
    (Get-Content "$resources\MSI Template.wxs" -Raw).Replace('.\.github\resources\', "$resources\") |
        Set-Content 'MSI Template.wxs' -Encoding utf8
    & "$wixDir\heat.exe" dir $appName -cg Application_Folder -dr App_Vendor_Folder -gg -ke -sfrag -sreg -template fragment -out application_folder.wxs
    & "$wixDir\candle.exe" -nologo -arch x64 -ext WixUIExtension -ext WixFirewallExtension `
        "-dAppName=$appName" "-dAppVersion=$appVersion" '-dAppVendor=Deep Symmetry, LLC' `
        '-dAppUpgradeCode=6D58C8D7-6163-43C6-93DC-A4C8CC1F81B6' `
        '-dAppDescription=Trigger events and automate shows in response to events on Pioneer CDJs' `
        '-dAppVendorFolder=Deep Symmetry' '-dAppIcon=BeatLink.ico' `
        'MSI Template.wxs' application_folder.wxs
    $msi = Join-Path $bltDir "target\Beat-Link-Trigger-$version-Win64.msi"
    & "$wixDir\light.exe" -nologo -b $appName -ext WixUIExtension -ext WixFirewallExtension -out $msi 'MSI Template.wixobj' application_folder.wixobj

    Write-Host "作成しました: $msi"
} finally {
    Pop-Location
}
