#!/bin/sh
# VCamUIPatch 一键编译 (macOS + theos)
# 用法:  ./build.sh          # 无参 = 编译 + 本地 deb
#        ./build.sh pkg      # 编译并把 dylib 复制到 ../patch/ 供打包器V6 使用
set -u

[ -n "${THEOS:-}" ] || THEOS=/opt/theos
export THEOS

if [ ! -d "$THEOS" ]; then
    echo "ERROR: theos 不存在于 $THEOS"
    echo "安装: git clone --recursive https://github.com/roothide/theos $THEOS"
    exit 1
fi

xcodebuild -version >/dev/null 2>&1 || { echo "ERROR: 需要 macOS + Xcode"; exit 1; }

make package FINALPACKAGE=1 || exit 1
echo "OK: .theos/_/Library/MobileSubstrate/DynamicLibraries/VCamUIPatch.dylib"

if [ "${1:-}" = "pkg" ]; then
    mkdir -p ../patch
    cp -f .theos/_/Library/MobileSubstrate/DynamicLibraries/VCamUIPatch.dylib ../patch/VCamUIPatch.dylib
    cp -f VCamUIPatch.plist ../patch/VCamUIPatch.plist
    echo "OK: 补丁已就位 ../patch/  -> 运行 python ../打包器V6/vcamv3_build_patch.py 即产出含补丁的 DEB"
fi