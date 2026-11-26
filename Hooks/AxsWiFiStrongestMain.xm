#import <UIKit/UIKit.h>
#import "AxsWiFiStrongestConfig.h"
#import "AxsWiFiStrongestEngine.h"
#import "AxsWiFiStrongestPrivate.h"

// 注入目标：SpringBoard（见 AxsWiFiStrongest.plist 的 com.apple.springboard）。
%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    [[AxsWiFiStrongestEngine axs_wifistrongest_shared] axs_wifistrongest_start];
}

%end

%ctor {
    @autoreleasepool {
        // 只加载配置快照，不扫描；扫描节奏完全交给引擎定时器。
        [AxsWiFiStrongestConfig axs_wifistrongest_shared];
        // 部分重启路径不会走 applicationDidFinishLaunching，补一条兜底启动。
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [[AxsWiFiStrongestEngine axs_wifistrongest_shared] axs_wifistrongest_start];
        });
    }
}
