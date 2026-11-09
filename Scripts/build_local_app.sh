#!/bin/bash
#
# 本地可测试 App。每次改动都跑一次，产出 dist/local/MacVerify.app，双击即可运行。
#
# 只编本机架构（Release），几十秒内出结果，用于改完立刻点开看。
# 对外分发的通用二进制 + DMG 走 Scripts/make_dmg.sh，那个只在 release 之后运行。
#
# 受限环境（编译器插件无法启动 macOS 沙箱）可加：
#   OTHER_SWIFT_FLAGS="-disable-sandbox" Scripts/build_local_app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

xcodebuild -project MacVerify.xcodeproj -scheme MacVerify \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build/local \
  CODE_SIGNING_ALLOWED=NO ${OTHER_SWIFT_FLAGS:+OTHER_SWIFT_FLAGS="$OTHER_SWIFT_FLAGS"} \
  build >/dev/null

rm -rf dist/local
mkdir -p dist/local
cp -R build/local/Build/Products/Release/MacVerify.app dist/local/MacVerify.app
codesign --force --deep -s - dist/local/MacVerify.app >/dev/null 2>&1

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
  dist/local/MacVerify.app/Contents/Info.plist)
build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" \
  dist/local/MacVerify.app/Contents/Info.plist)

echo "可测试 App：dist/local/MacVerify.app（$version ($build)）"
