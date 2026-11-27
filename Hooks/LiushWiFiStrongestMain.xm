#import <UIKit/UIKit.h>
#import "LiushWiFiStrongestConfig.h"
#import "LiushWiFiStrongestEngine.h"
#import "LiushWiFiStrongestPrivate.h"

// 注入目标：SpringBoard（见 LiushWiFiStrongest.plist 的 com.apple.springboard）。
%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    [[LiushWiFiStrongestEngine liush_wifistrongest_shared] liush_wifistrongest_start];
}

%end

%ctor {
    @autoreleasepool {
        // 本 dylib 同时注入 SpringBoard 与 Preferences：引擎只在 SpringBoard 里跑。
        NSString *process = [[NSProcessInfo processInfo] processName];
        if (![process isEqualToString:@"SpringBoard"]) return;
        // 只加载配置快照，不扫描；扫描节奏完全交给引擎定时器。
        [LiushWiFiStrongestConfig liush_wifistrongest_shared];
        // 部分重启路径不会走 applicationDidFinishLaunching，补一条兜底启动。
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [[LiushWiFiStrongestEngine liush_wifistrongest_shared] liush_wifistrongest_start];
        });
    }
}
