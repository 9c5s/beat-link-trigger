#!/bin/zsh
# fork 版の beat-link と BLT をビルドし、macOS 用のディスクイメージを target/ に作る
# 使い方: zsh scripts/build_dmg.zsh（beat-link は BLT と同じ親ディレクトリに clone しておく）

set -euo pipefail

blt_dir=${0:A:h:h}
beat_link_dir=${BEAT_LINK_DIR:-${blt_dir:h}/beat-link}

export JAVA_HOME=${JAVA_HOME:-$(/usr/libexec/java_home -v 21)}
export PATH="$JAVA_HOME/bin:$PATH"

echo "beat-link をビルドしています。"
(cd "$beat_link_dir" && mvn -q -Dgpg.skip -Dmaven.javadoc.skip=true clean install)

echo "BLT をビルドしています。"
cd "$blt_dir"
npm install --no-fund --no-audit
lein uberjar

version=$(sed -E 's/.*:version "([^"]+)".*/\1/' resources/beat_link_trigger/version.edn)
# jpackage は数字だけのバージョンしか受け付けない
app_version=${version%%-*}

work=target/dmg
rm -rf "$work"
mkdir -p "$work/input"
cp target/beat-link-trigger.jar "$work/input/"

echo "ディスクイメージを作成しています。"
jpackage --name "Beat Link Trigger" --input "$work/input" --dest "$work" \
         --add-modules java.base,java.desktop,java.management,java.naming,java.prefs,java.sql,jdk.javadoc,jdk.zipfs,jdk.unsupported \
         --java-options "-XX:+UseZGC" \
         --icon .github/resources/BeatLink.icns --main-jar beat-link-trigger.jar \
         --description "Trigger events and automate shows in response to events on Pioneer CDJs" \
         --copyright "© 2016-2024 Deep Symmetry, LLC" --vendor "Deep Symmetry, LLC" \
         --mac-package-identifier "org.deepsymmetry.beat-link-trigger" --app-version "$app_version"

dmg="target/Beat-Link-Trigger-$version-MacOS.dmg"
mv "$work/Beat Link Trigger-$app_version.dmg" "$dmg"
echo "作成しました: $dmg"
