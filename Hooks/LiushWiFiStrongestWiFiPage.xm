#import <UIKit/UIKit.h>
#import "LiushWiFiStrongestConfig.h"
#import "LiushWiFiStrongestLog.h"
#import "LiushWiFiStrongestPaths.h"
#import "LiushWiFiStrongestPreferences.h"

// GoodWiFi 那套「在系统 WiFi 页里直接看 MAC / 信号」的内嵌实现。
//
// 原则（都为防崩设计）：
// 1. 只在 Preferences 进程挂载（ctor 里做进程判断）；
// 2. 系统类 WiFiSettingsController 不存在就完全不挂载，只写一行日志；
// 3. 每行叠信息前后任何异常都吞掉，绝不影响设置本身；
// 4. 数据来源是 SpringBoard 写好的快照文件，本进程不扫描（没有 entitlement）。

static NSDictionary *liush_wifistrongest_pageSnapshot(NSDate **stamp, NSDate *now) {
    static NSDictionary *cached;
    static NSDate *cachedAt;
    if (!cached || !cachedAt || -[cachedAt timeIntervalSinceNow] < -2.0) {
        NSString *path = liush_wifistrongest_snapshotPath();
        NSData *data = path.length ? [NSData dataWithContentsOfFile:path] : nil;
        id decoded = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        cached = [decoded isKindOfClass:[NSDictionary class]] ? decoded : @{};
        cachedAt = now;
    }
    if (stamp) *stamp = cachedAt;
    return cached;
}

// 找得到对应网络就返回后缀（"-58dBm·5G·b8:27:eb:..."），找不到返回 nil。
static NSString *liush_wifistrongest_suffixForSSID(NSString *ssid) {
    LiushWiFiStrongestConfig *config = [LiushWiFiStrongestConfig liush_wifistrongest_shared];
    if (![config liush_wifistrongest_boolForKey:@"pageEnhance" defaultValue:YES]) return nil;

    NSDate *unused = nil;
    NSDictionary *snapshot = liush_wifistrongest_pageSnapshot(&unused, [NSDate date]);
    NSArray *networks = snapshot[@"networks"];
    if (![networks isKindOfClass:[NSArray class]]) return nil;

    NSDictionary *hit = nil;
    for (id item in networks) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        if ([item[@"ssid"] isKindOfClass:[NSString class]] && [item[@"ssid"] isEqualToString:ssid]) {
            hit = item;
            break;
        }
    }
    if (!hit) return nil;

    NSInteger rssi = [hit[@"rssi"] integerValue];
    if (rssi >= 0 || rssi <= -100) return nil;

    NSMutableString *suffix = [NSMutableString stringWithFormat:@" -%lddBm·%@",
        (long)(rssi * -1), [hit[@"is5g"] boolValue] ? @"5G" : @"2.4G"];
    if ([config liush_wifistrongest_boolForKey:@"pageShowMAC" defaultValue:YES]) {
        NSString *bssid = hit[@"bssid"];
        if ([bssid isKindOfClass:[NSString class]] && bssid.length > 3 &&
            ![bssid isEqualToString:@"未知"]) {
            [suffix appendFormat:@"·%@", bssid];
        }
    }
    return suffix;
}

// 系统 WiFi 页的行是私有 cell，标签位置逐版本变；按 公开 textLabel → KVC label → contentView 首个 UILabel 的顺序找。
static UILabel *liush_wifistrongest_labelForCell(UITableViewCell *cell) {
    UILabel *label = cell.textLabel;
    if (!label) {
        @try {
            id viaKey = [cell valueForKey:@"label"];
            if ([viaKey isKindOfClass:[UILabel class]]) label = viaKey;
        } @catch (__unused NSException *exception) {}
    }
    if (!label) {
        for (UIView *sub in cell.contentView.subviews) {
            if ([sub isKindOfClass:[UILabel class]]) {
                label = (UILabel *)sub;
                break;
            }
        }
    }
    return label;
}

%group LiushWiFiPage

%hook WiFiSettingsController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    LiushWiFiStrongestConfig *config = [LiushWiFiStrongestConfig liush_wifistrongest_shared];
    if (![config liush_wifistrongest_boolForKey:@"pageEnhance" defaultValue:YES]) return;
    // 进页面就让 SpringBoard 重扫一次，随后滚动/刷新即可拿到新快照。
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)LiushWiFiStrongestForceScanNotification, NULL, NULL, true);
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell
      forRowAtIndexPath:(NSIndexPath *)indexPath {
    %orig;
    @try {
        UILabel *label = liush_wifistrongest_labelForCell(cell);
        if (!label) return;
        NSString *title = label.text;
        if (![title isKindOfClass:[NSString class]] || title.length == 0) return;
        // willDisplayCell 会随滚动反复回调，带后缀就说明本轮已处理过。
        if ([title containsString:@"dBm"]) return;
        NSString *suffix = liush_wifistrongest_suffixForSSID(title);
        if (suffix.length == 0) return;
        label.text = [title stringByAppendingString:suffix];
    } @catch (__unused NSException *exception) {
        // 系统 WiFi 页任何私有 UI 变化都不允许波及设置本身
    }
}

%end

%end

%ctor {
    @autoreleasepool {
        NSString *process = [[NSProcessInfo processInfo] processName];
        if (![process isEqualToString:@"Preferences"]) return;
        if (!NSClassFromString(@"WiFiSettingsController")) {
            [LiushWiFiStrongestLog liush_wifistrongest_log:@"WiFi 页增强：未找到 WiFiSettingsController，未挂载"];
            return;
        }
        %init(LiushWiFiPage);
        [LiushWiFiStrongestLog liush_wifistrongest_log:@"WiFi 页增强：已挂载到 WiFiSettingsController"];
    }
}
