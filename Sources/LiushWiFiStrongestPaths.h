#pragma once

#import <Foundation/Foundation.h>

#ifdef THEOS_PACKAGE_SCHEME_ROOTHIDE
#import <roothide.h>
#else
#import <rootless.h>
#endif

static inline NSString *liush_wifistrongest_resourcePath(NSString *rootfsPath) {
#ifdef THEOS_PACKAGE_SCHEME_ROOTHIDE
    return jbroot(rootfsPath);
#else
    return ROOT_PATH_NS_VAR(rootfsPath);
#endif
}

static inline NSString *liush_wifistrongest_preferencesPath(void) {
    NSString *path = @"/var/mobile/Library/Preferences/com.liush.wifistrongest.plist";
#ifdef THEOS_PACKAGE_SCHEME_ROOTHIDE
    return jbroot(path);
#else
    // Mobile user preferences do not use the rootless installation prefix.
    return path;
#endif
}

// SpringBoard 侧把扫描详情写到手机用户可读的缓存目录，设置面板（Preferences 进程）直接读。
// 面板进程拿不到 wlan entitlement，所以不能自己扫描，只能读这份快照。
static inline NSString *liush_wifistrongest_snapshotPath(void) {
    NSString *path = @"/var/mobile/Library/Caches/com.liush.wifistrongest/snapshot.json";
#ifdef THEOS_PACKAGE_SCHEME_ROOTHIDE
    return jbroot(path);
#else
    return path;
#endif
}
