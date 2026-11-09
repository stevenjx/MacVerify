#!/bin/bash
#
# 通用二进制 DMG。只在「GitHub 上已经存在对应 release」之后才允许运行：
# 有包但没发布的状态会让用户下到没有对应说明的版本，也会让版本号失去意义。
#
# 流程：改代码 → 提交并推送 → 建 release（CI 会自动构建并上传 dmg）
#       → 需要本地留档时再跑这个脚本。
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(grep -m1 'MARKETING_VERSION = ' MacVerify.xcodeproj/project.pbxproj \
  | sed 's/.*MARKETING_VERSION = //; s/;.*//')

if ! gh release view "v$version" >/dev/null 2>&1; then
  echo "v$version 还没有发布。按流程先生成 release，再打 dmg。" >&2
  echo "（release 由 CI 构建并上传 dmg；本地留档可在发布后再跑本脚本。）" >&2
  exit 1
fi

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

xcodebuild -project MacVerify.xcodeproj -scheme MacVerify \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath build/release \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO ${OTHER_SWIFT_FLAGS:+OTHER_SWIFT_FLAGS="$OTHER_SWIFT_FLAGS"} \
  build >/dev/null

rm -rf dist/staging
mkdir -p dist/staging
cp -R build/release/Build/Products/Release/MacVerify.app dist/staging/
ln -s /Applications dist/staging/Applications
codesign --force --deep -s - dist/staging/MacVerify.app

dmg="dist/MacVerify-$version.dmg"
hdiutil create -volname "MacVerify" -srcfolder dist/staging -ov -format UDZO "$dmg" >/dev/null

# 挂载实测：架构与版本号必须与发布说明一致，不能只看文件名
mount=$(hdiutil attach -nobrowse -readonly "$dmg" | grep -o '/Volumes/.*' | tail -1)
trap 'hdiutil detach "$mount" >/dev/null 2>&1 || true' EXIT
lipo -info "$mount/MacVerify.app/Contents/MacOS/MacVerify"
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
  "$mount/MacVerify.app/Contents/Info.plist"

echo "DMG：$dmg"
