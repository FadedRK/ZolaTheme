TARGET = iphone:clang:latest:15.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ZaloProbe

ZaloProbe_FILES = Tweak.x
ZaloProbe_CFLAGS = -fobjc-arc
ZaloProbe_FRAMEWORKS = UIKit UniformTypeIdentifiers

# Use Logos' internal Objective-C runtime generator.
# This produces the tweak dylib without invoking Debian packaging.
ZaloProbe_LOGOS_DEFAULT_GENERATOR = internal

include $(THEOS_MAKE_PATH)/tweak.mk
