# VCamUIPatch — 双体悬浮舱 UI 补丁 (纯 ObjC 运行时, 无 substrate 符号依赖)
# 构建要求: macOS + Xcode + theos (roothide fork) + iPhoneOS16.x SDK
# 用法: make package FINALPACKAGE=1  (产物在 .theos/_/Library/MobileSubstrate/DynamicLibraries/)

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VCamUIPatch

VCamUIPatch_FILES = VCamUIPatch.m
VCamUIPatch_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable -miphoneos-version-min=16.0
# 本补丁不引用 substrate 符号: 清空默认链接库, 符号运行时动态解析
VCamUIPatch_LIBRARIES =
VCamUIPatch_LDFLAGS = -Wl,-undefined,dynamic_lookup -Wl,-platform_version,ios,16.0,16.0

# 覆盖默认架构 (arm64e 需 Xcode 15 + 匹配 SDK; 仅 arm64 时去掉 arm64e)
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:16.0
# 显式部署版本: tweak.mk 可能重置 TARGET, 双保险 (maskedCorners 需 iOS 11+)
TARGET_IPHONEOS_DEPLOYMENT_VERSION = 16.0

include $(THEOS_MAKE_PATH)/tweak.mk

after-stage::
	@echo "patch staged: $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/VCamUIPatch.dylib"