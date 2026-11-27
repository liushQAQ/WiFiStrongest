#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "LiushWiFiStrongestConfig.h"
#import "LiushWiFiStrongestLog.h"
#import "LiushWiFiStrongestPaths.h"
#import "LiushWiFiStrongestPreferences.h"

// GoodWiFi 那套「在系统 WiFi 页里直接看 MAC / 信号」的内嵌实现。
//
// v5.2.4 改为运行时自动发现，不再硬编码单一类名（v5.2.3 真机没生效，多半是
// iOS 17/18 上类名与 WiFiSettingsController 不一致）：
// 1. 只在 Preferences 进程挂载；
// 2. 枚举全部名字以 WiFi 开头且含 Controller 的 UIViewController 子类，
//    凡实现了表格 willDisplay 的统统挂钩——挂到哪个类写日志记下哪个；
// 3. 标签匹配不再猜位置：递归收集 cell 里所有 UILabel，文本与快照里的
//    SSID 精确相等的才追加后缀，追加前用关联对象记住原始标题防重复；
// 4. 进入页面自动让 SpringBoard 重扫一次，并记录快照网络数，日志可自诊断；
// 5. 任何异常吞掉，绝不影响设置本身。

// ---------- 快照读取（2s 缓存） ----------

static NSDictionary *liush_wifistrongest_pageSnapshot(void) {
    static NSDictionary *cached;
    static NSDate *cachedAt;
    NSDate *now = [NSDate date];
    if (!cachedAt || -[cachedAt timeIntervalSinceDate:now] < -2.0) {
        NSString *path = liush_wifistrongest_snapshotPath();
        NSData *data = path.length ? [NSData dataWithContentsOfFile:path] : nil;
        id decoded = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        cached = [decoded isKindOfClass:[NSDictionary class]] ? decoded : @{};
        cachedAt = now;
    }
    return cached;
}

// ssid -> " -58dBm·5G·b8:27:eb:..." 的映射，每次取快照时重建。
static NSDictionary<NSString *, NSString *> *liush_wifistrongest_suffixMap(void) {
    LiushWiFiStrongestConfig *config = [LiushWiFiStrongestConfig liush_wifistrongest_shared];
    BOOL wantSignal = [config liush_wifistrongest_boolForKey:@"pageEnhance" defaultValue:YES];
    if (!wantSignal) return @{};
    BOOL wantMAC = [config liush_wifistrongest_boolForKey:@"pageShowMAC" defaultValue:YES];

    NSArray *networks = liush_wifistrongest_pageSnapshot()[@"networks"];
    if (![networks isKindOfClass:[NSArray class]]) return @{};

    NSMutableDictionary<NSString *, NSString *> *map = [NSMutableDictionary dictionary];
    for (id item in networks) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSString *ssid = item[@"ssid"];
        if (![ssid isKindOfClass:[NSString class]] || ssid.length == 0) continue;
        NSInteger rssi = [item[@"rssi"] integerValue];
        if (rssi >= 0 || rssi <= -100) continue;
        NSMutableString *suffix = [NSMutableString stringWithFormat:@" -%lddBm·%@",
            (long)(rssi * -1), [item[@"is5g"] boolValue] ? @"5G" : @"2.4G"];
        NSString *bssid = item[@"bssid"];
        if (wantMAC && [bssid isKindOfClass:[NSString class]] && bssid.length > 3 &&
            ![bssid isEqualToString:@"未知"]) {
            [suffix appendFormat:@"·%@", bssid];
        }
        // 同名网络取信号最强的那条。
        NSString *existing = map[ssid];
        if (!existing || [suffix length] > 0) map[ssid] = suffix;
    }
    return map;
}

// ---------- 标签递归查找 ----------

static void liush_wifistrongest_collectLabels(UIView *view, NSMutableArray<UILabel *> *out) {
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:[UILabel class]]) [out addObject:(UILabel *)sub];
        liush_wifistrongest_collectLabels(sub, out);
    }
}

static void liush_wifistrongest_decorateCell(UITableViewCell *cell) {
    NSDictionary<NSString *, NSString *> *map = liush_wifistrongest_suffixMap();
    if (map.count == 0) return;
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    liush_wifistrongest_collectLabels(cell, labels);
    for (UILabel *label in labels) {
        NSString *text = label.text;
        if (![text isKindOfClass:[NSString class]] || text.length == 0) continue;
        // 原始标题记在关联对象里；没有说明第一次见到，清理旧后缀后记录。
        NSString *base = objc_getAssociatedObject(label, @selector(liushBase));
        if (!base) {
            NSRange dash = [text rangeOfString:@" -"];
            base = dash.location > 0 ? [text substringToIndex:dash.location] : text;
            objc_setAssociatedObject(label, @selector(liushBase), base,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (![map objectForKey:base]) continue;
        NSString *decorated = [base stringByAppendingString:map[base]];
        if (![decorated isEqualToString:text]) {
            label.text = decorated;
        }
        break;  // 一个 cell 只装饰主标题所在的第一枚命中标签
    }
}

// ---------- 运行时挂钩 ----------

static void (*orig_viewWillAppear)(id, SEL, BOOL);
static void liush_wifistrongest_hookViewAppear(id self, SEL _cmd, BOOL animated) {
    orig_viewWillAppear(self, _cmd, animated);
    @try {
        static NSMutableSet *seen;
        static dispatch_once_t once;
        dispatch_once(&once, ^{ seen = [NSMutableSet set]; });
        NSString *key = NSStringFromClass([self class]);
        if (![seen containsObject:key]) {
            [seen addObject:key];
            NSDictionary *snapshot = liush_wifistrongest_pageSnapshot();
            NSArray *networks = snapshot[@"networks"];
            [LiushWiFiStrongestLog liush_wifistrongest_log:@"WiFi 页：进入 %@，快照 %@ 个网络",
                key, [networks isKindOfClass:[NSArray class]]
                    ? [NSString stringWithFormat:@"%lu", (unsigned long)networks.count]
                    : @"无"];
        }
        LiushWiFiStrongestConfig *config = [LiushWiFiStrongestConfig liush_wifistrongest_shared];
        if (![config liush_wifistrongest_boolForKey:@"pageEnhance" defaultValue:YES]) return;
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            (__bridge CFStringRef)LiushWiFiStrongestForceScanNotification, NULL, NULL, true);
    } @catch (__unused NSException *e) {}
}

static void (*orig_willDisplay)(id, SEL, UITableView *, UITableViewCell *, NSIndexPath *);
static void liush_wifistrongest_hookWillDisplay(id self, SEL _cmd, UITableView *tableView, UITableViewCell *cell,
                             NSIndexPath *indexPath) {
    orig_willDisplay(self, _cmd, tableView, cell, indexPath);
    @try {
        liush_wifistrongest_decorateCell(cell);
    } @catch (__unused NSException *e) {
        // 系统 WiFi 页任何私有 UI 变化都不允许波及设置本身
    }
}

%ctor {
    @autoreleasepool {
        NSString *process = [[NSProcessInfo processInfo] processName];
        if (![process isEqualToString:@"Preferences"]) return;

        // 枚举全部 WiFi*Controller 的 UIViewController 子类，能处理表格行的全挂。
        unsigned int count = 0;
        Class *classes = objc_copyClassList(&count);
        NSMutableArray<NSString *> *hooked = [NSMutableArray array];
        SEL displaySel = @selector(tableView:willDisplayCell:forRowAtIndexPath:);
        SEL appearSel = @selector(viewWillAppear:);
        for (unsigned int i = 0; i < count; i++) {
            Class cls = classes[i];
            const char *name = class_getName(cls);
            const char *p = name;
            if (p[0] != 'W' || p[1] != 'i' || p[2] != 'F' || p[3] != 'i') continue;
            NSString *clsName = [NSString stringWithUTF8String:name];
            if (![clsName containsString:@"Controller"]) continue;
            if (![cls isSubclassOfClass:[UIViewController class]]) continue;
            Method display = class_getInstanceMethod(cls, displaySel);
            Method appear = class_getInstanceMethod(cls, appearSel);
            BOOL didHook = NO;
            if (display) {
                MSHookMessageEx(cls, displaySel, (IMP)liush_wifistrongest_hookWillDisplay, (IMP *)&orig_willDisplay);
                didHook = YES;
            }
            if (appear) {
                MSHookMessageEx(cls, appearSel, (IMP)liush_wifistrongest_hookViewAppear, (IMP *)&orig_viewWillAppear);
                didHook = YES;
            }
            if (didHook) [hooked addObject:clsName];
        }
        free(classes);

        if (hooked.count == 0) {
            [LiushWiFiStrongestLog liush_wifistrongest_log:
                @"WiFi 页增强：未找到任何 WiFi*Controller 类，未挂载"];
        } else {
            [LiushWiFiStrongestLog liush_wifistrongest_log:@"WiFi 页增强：已挂载 %lu 个类：%@",
                (unsigned long)hooked.count, [hooked componentsJoinedByString:@", "]];
        }
    }
}
