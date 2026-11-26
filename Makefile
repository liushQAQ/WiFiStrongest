DEBUG = 0
FINALPACKAGE = 1

ARCHS = arm64 arm64e

# Share the SDK and deployment targets with the PreferenceBundle.
include LiushWiFiStrongestBuild.mk
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LiushWiFiStrongest
LiushWiFiStrongest_FILES = $(wildcard Hooks/*.xm Sources/*.m)
LiushWiFiStrongest_CFLAGS = -fobjc-arc -I./Headers -I./Sources
LiushWiFiStrongest_FRAMEWORKS = UIKit Foundation CoreFoundation
LiushWiFiStrongest_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += LiushWiFiStrongestPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk
