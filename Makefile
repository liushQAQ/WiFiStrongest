DEBUG = 0
FINALPACKAGE = 1

ARCHS = arm64 arm64e

# Share the SDK and deployment targets with the PreferenceBundle.
include AxsWiFiStrongestBuild.mk
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AxsWiFiStrongest
AxsWiFiStrongest_FILES = $(wildcard Hooks/*.xm Sources/*.m)
AxsWiFiStrongest_CFLAGS = -fobjc-arc -I./Headers -I./Sources
AxsWiFiStrongest_FRAMEWORKS = UIKit Foundation CoreFoundation
AxsWiFiStrongest_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += AxsWiFiStrongestPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk
