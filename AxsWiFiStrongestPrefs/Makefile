include ../AxsWiFiStrongestBuild.mk
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = AxsWiFiStrongestPrefs
# 面板进程不加载 tweak dylib，日志与配置读取直接共用同一份源码。
AxsWiFiStrongestPrefs_FILES = $(wildcard *.m) \
	../Sources/AxsWiFiStrongestConfig.m \
	../Sources/AxsWiFiStrongestLog.m
AxsWiFiStrongestPrefs_CFLAGS = -fobjc-arc -I../Sources
AxsWiFiStrongestPrefs_FRAMEWORKS = UIKit Foundation CoreFoundation
AxsWiFiStrongestPrefs_PRIVATE_FRAMEWORKS = Preferences
AxsWiFiStrongestPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
