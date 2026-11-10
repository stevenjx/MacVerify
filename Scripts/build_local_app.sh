#!/bin/bash
#
# 本地可测试 App。每次改动都跑一次，产出 dist/local/MacVerify.app，双击即可运行。
#
# 默认只编本机架构（Release），几十秒内出结果，用于改完立刻点开看。
# 要拷到架构不同的另一台 Mac（比如 Intel 机器），加 --universal 编通用二进制——
# 否则对方只会看到 “this application is not supported on this Mac”。
#
# 对外分发的通用二进制 + DMG 走 Scripts/make_dmg.sh，那个只在 release 之后运行。
#
# 受限环境（编译器插件无法启动 macOS 沙箱）可加：
#   OTHER_SWIFT_FLAGS="-disable-sandbox" Scripts/build_local_app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

universal=0
for arg in "$@"; do
  case "$arg" in
    --universal) universal=1 ;;
    -h|--help)
      echo "用法：Scripts/build_local_app.sh [--universal]"
      echo "  --universal  同时编译 arm64 与 x86_64，可拷给另一台架构不同的 Mac"
      exit 0
      ;;
    *) echo "未知参数：$arg（试试 --help）" >&2; exit 2 ;;
  esac
done

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

arch_flags=()
if [ "$universal" = "1" ]; then
  arch_flags=(ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO)
fi

xcodebuild -project MacVerify.xcodeproj -scheme MacVerify \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build/local \
  CODE_SIGNING_ALLOWED=NO ${OTHER_SWIFT_FLAGS:+OTHER_SWIFT_FLAGS="$OTHER_SWIFT_FLAGS"} \
  ${arch_flags[@]+"${arch_flags[@]}"} \
  build >/dev/null

rm -rf dist/local
mkdir -p dist/local
cp -R build/local/Build/Products/Release/MacVerify.app dist/local/MacVerify.app
codesign --force --deep -s - dist/local/MacVerify.app >/dev/null 2>&1

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
  dist/local/MacVerify.app/Contents/Info.plist)
build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" \
  dist/local/MacVerify.app/Contents/Info.plist)
archs=$(lipo -archs dist/local/MacVerify.app/Contents/MacOS/MacVerify)

echo "可测试 App：dist/local/MacVerify.app（${version} (${build})，${archs}）"

if [ "$universal" = "0" ]; then
  echo "提示：这是单架构包（${archs}），只适合本机测试；拷到另一架构的 Mac 会提示 “not supported on this Mac”。"
  echo "      要给别的电脑用，加 --universal 重新编译。"
fi
