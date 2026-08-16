# VCamUIPatch — 双体悬浮舱 UI 补丁 (纯 ObjC 运行时, 无 substrate 符号依赖)
# 构建要求: macOS + Xcode + theos (roothide fork) + iPhoneOS16.x SDK
# 用法: make package FINALPACKAGE=1  (产物在 .theos/_/Library/MobileSubstrate/DynamicLibraries/)

# 注意: TARGET 必须在 include common.mk 之前声明, 否则 theos 使用默认 9.0
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:16.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VCamUIPatch

VCamUIPatch_FILES = VCamUIPatch.m
VCamUIPatch_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable
# 本补丁不引用 substrate 符号: 清空默认链接库, 符号运行时动态解析
VCamUIPatch_LIBRARIES =
VCamUIPatch_LDFLAGS = -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk

after-stage::
	@echo "patch staged: $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/VCamUIPatch.dylib"