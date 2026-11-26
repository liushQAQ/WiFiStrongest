include ../LiushWiFiStrongestBuild.mk
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = LiushWiFiStrongestPrefs
# 面板进程不加载 tweak dylib，日志与配置读取直接共用同一份源码。
LiushWiFiStrongestPrefs_FILES = $(wildcard *.m) \
	../Sources/LiushWiFiStrongestConfig.m \
	../Sources/LiushWiFiStrongestLog.m
LiushWiFiStrongestPrefs_CFLAGS = -fobjc-arc -I../Sources
LiushWiFiStrongestPrefs_FRAMEWORKS = UIKit Foundation CoreFoundation
LiushWiFiStrongestPrefs_PRIVATE_FRAMEWORKS = Preferences
LiushWiFiStrongestPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
