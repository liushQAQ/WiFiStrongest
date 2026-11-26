#import "LiushWiFiStrongestEngine.h"
#import "LiushWiFiStrongestConfig.h"
#import "LiushWiFiStrongestLog.h"
#import "LiushWiFiStrongestMobileWiFi.h"
#import "LiushWiFiStrongestPreferences.h"
#import "LiushWiFiStrongestVersion.h"
#import <objc/message.h>

// C 回调在本类实现之前就要引用自检方法，这里前置声明。
@interface LiushWiFiStrongestEngine (LiushSelfCheck)
- (void)liush_wifistrongest_selfCheck;
@end

static const NSTimeInterval LiushWiFiStrongestTickInterval = 5.0;
static const NSTimeInterval LiushWiFiStrongestPostSwitchQuiet = 20.0;

// 把扫描详情落盘，供设置面板的「WiFi 详情」页读取。
// 面板进程没有 wlan entitlement，不能自己扫描，只能读这份快照。
static void liush_wifistrongest_writeSnapshot(NSDictionary *snapshot) {
    if (![snapshot isKindOfClass:[NSDictionary class]]) return;
    NSString *path = liush_wifistrongest_snapshotPath();
    if (path.length == 0) return;
    NSFileManager *manager = [NSFileManager defaultManager];
    [manager createDirectoryAtPath:[path stringByDeletingLastPathComponent]
       withIntermediateDirectories:YES attributes:nil error:NULL];
    NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:0 error:NULL];
    if (data) [data writeToFile:path options:NSDataWritingAtomic error:NULL];
}

// 百分比化信号质量：-100dBm→0，-50dBm 及以上→100。
static double liush_wifistrongest_quality(NSInteger rssi) {
    if (rssi >= -50) return 100.0;
    if (rssi <= -100) return 0.0;
    return (double)(rssi + 100);
}

static void liush_wifistrongest_forceScanCallback(CFNotificationCenterRef center, void *observer,
                                              CFStringRef name, const void *object,
                                              CFDictionaryRef info) {
    LiushWiFiStrongestEngine *engine = (__bridge LiushWiFiStrongestEngine *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [engine liush_wifistrongest_forceScan];
    });
}

static void liush_wifistrongest_selfCheckCallback(CFNotificationCenterRef center, void *observer,
                                              CFStringRef name, const void *object,
                                              CFDictionaryRef info) {
    LiushWiFiStrongestEngine *engine = (__bridge LiushWiFiStrongestEngine *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [engine liush_wifistrongest_selfCheck];
    });
}

@interface LiushWiFiStrongestEngine ()
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *cooldowns;
@property (nonatomic, strong) NSDate *lastEvaluation;
@property (nonatomic, strong) NSDate *lastSwitch;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) BOOL pendingForced;
@property (nonatomic, assign) NSInteger tickCount;
@property (nonatomic, assign) NSInteger lastScanCount;
// 上一次写进日志的「为什么没动作」，用于去重，避免每 5 秒刷一行。
@property (nonatomic, copy) NSString *lastReason;
@end

@implementation LiushWiFiStrongestEngine

+ (instancetype)liush_wifistrongest_shared {
    static LiushWiFiStrongestEngine *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.liush.wifistrongest.engine", DISPATCH_QUEUE_SERIAL);
        _cooldowns = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)liush_wifistrongest_start {
    if (self.running) return;
    self.running = YES;
    [LiushWiFiStrongestConfig liush_wifistrongest_shared];
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)self, liush_wifistrongest_forceScanCallback,
        (__bridge CFStringRef)LiushWiFiStrongestForceScanNotification, NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);
    self.timer = [NSTimer scheduledTimerWithTimeInterval:LiushWiFiStrongestTickInterval
                                                  target:self
                                                selector:@selector(liush_wifistrongest_tick:)
                                                userInfo:nil
                                                 repeats:YES];
    self.timer.tolerance = 1.0;
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)self, liush_wifistrongest_selfCheckCallback,
        (__bridge CFStringRef)LiushWiFiStrongestSelfCheckNotification, NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);
    [LiushWiFiStrongestLog liush_wifistrongest_log:@"引擎启动 v%s，静默校验间隔 %.0fs",
        LIUSH_WIFISTRONGEST_VERSION, LiushWiFiStrongestTickInterval];
    [self liush_wifistrongest_selfCheck];
}

// 一段能独立看懂的自检：即使「详细日志」是关的，也写进日志。
// 目的是让老总只发这一段就能定位问题，不用猜。
- (void)liush_wifistrongest_selfCheck {
    LiushWiFiStrongestConfig *config = [LiushWiFiStrongestConfig liush_wifistrongest_shared];
    LiushWiFiStrongestMobileWiFi *wifi = [LiushWiFiStrongestMobileWiFi liush_wifistrongest_shared];
    BOOL enabled = [config liush_wifistrongest_isEnabled];
    BOOL canScan = [wifi liush_wifistrongest_canScan];

    NSString *ssid = nil;
    NSInteger rssi = 0;
    NSInteger channel = 0;
    BOOL connected = [wifi liush_wifistrongest_readCurrentSSID:&ssid rssi:&rssi channel:&channel];

    NSInteger interval = MAX((NSInteger)5, [config liush_wifistrongest_integerForKey:@"scanInterval" defaultValue:20]);
    NSInteger forceThreshold = [config liush_wifistrongest_integerForKey:@"forceThreshold" defaultValue:-80];
    NSInteger intervalThreshold = [config liush_wifistrongest_integerForKey:@"intervalThreshold" defaultValue:-65];
    NSInteger minDelta = [config liush_wifistrongest_integerForKey:@"minDelta" defaultValue:8];
    NSInteger cooldown = [config liush_wifistrongest_integerForKey:@"failCooldown" defaultValue:300];

    [LiushWiFiStrongestLog liush_wifistrongest_log:@"==== 自检 v%s · 进程 %@ ====",
        LIUSH_WIFISTRONGEST_VERSION, [[NSProcessInfo processInfo] processName]];
    [LiushWiFiStrongestLog liush_wifistrongest_log:@"总开关：%@",
        enabled ? @"已启用" : @"已关闭（设置里打开「启用插件」后才会工作）"];
    [LiushWiFiStrongestLog liush_wifistrongest_log:@"扫描能力：%@ | %@",
        canScan ? @"可用" : @"不可用", [wifi liush_wifistrongest_diagnostic]];
    [LiushWiFiStrongestLog liush_wifistrongest_log:@"当前网络：%@",
        connected ? [NSString stringWithFormat:@"%@ %lddBm 信道 %ld", ssid, (long)rssi, (long)channel]
                  : @"未连接"];
    [LiushWiFiStrongestLog liush_wifistrongest_log:
        @"参数：间隔 %lds | 强制阈值 %ld | 区间阈值 %ld | 最小差值 %ld | 失败冷却 %lds | 白名单 %lu 个 | 5G偏好 %@ | 未连接自动连 %@ | 锁屏跳过 %@ | 详细日志 %@",
        (long)interval, (long)forceThreshold, (long)intervalThreshold, (long)minDelta, (long)cooldown,
        (unsigned long)[config liush_wifistrongest_whitelist].count,
        [config liush_wifistrongest_prefer5G] ? @"开" : @"关",
        [config liush_wifistrongest_boolForKey:@"autoJoinWhenDisconnected" defaultValue:NO] ? @"开" : @"关",
        [config liush_wifistrongest_skipWhenLocked] ? @"开" : @"关",
        [config liush_wifistrongest_debugLog] ? @"开" : @"关"];

    if (!canScan) {
        [LiushWiFiStrongestLog liush_wifistrongest_log:
            @"结论：扫描与切换不可用（缺 wlan entitlement 或私有符号），只能给只读信号。"];
    } else if (!enabled) {
        [LiushWiFiStrongestLog liush_wifistrongest_log:@"结论：能力正常，但总开关关着，本轮不会扫描。"];
    } else {
        [LiushWiFiStrongestLog liush_wifistrongest_log:@"结论：能力与开关都正常，等待节拍判定。"];
    }
    [LiushWiFiStrongestLog liush_wifistrongest_log:@"==== 自检结束 ===="];
}

// 同一个原因只写一次，除非中途真的做过动作（做动作时会把 lastReason 清空）。
- (void)liush_wifistrongest_note:(NSString *)reason {
    if (reason.length == 0) return;
    if (self.lastReason && [self.lastReason isEqualToString:reason]) return;
    self.lastReason = reason;
    [LiushWiFiStrongestLog liush_wifistrongest_log:@"%@", reason];
}

- (void)liush_wifistrongest_reloadTimer {
    // 间隔完全由配置驱动，定时器保持静默节拍，无需重建。
}

- (void)liush_wifistrongest_forceScan {
    [LiushWiFiStrongestLog liush_wifistrongest_log:@"收到手动扫描请求"];
    [self liush_wifistrongest_enqueueForced:YES];
}

- (void)liush_wifistrongest_tick:(NSTimer *)timer {
    LiushWiFiStrongestConfig *config = [LiushWiFiStrongestConfig liush_wifistrongest_shared];
    if (![config liush_wifistrongest_isEnabled]) {
        [self liush_wifistrongest_note:@"节拍暂停：总开关未启用（设置 → WiFi 择优切换 → 启用插件）"];
        return;
    }
    if ([config liush_wifistrongest_skipWhenLocked] && [self liush_wifistrongest_screenIsLocked]) {
        [self liush_wifistrongest_note:@"节拍暂停：锁屏中（可关掉「锁屏时不扫描」）"];
        return;
    }
    self.tickCount += 1;
    if (self.tickCount % 60 == 0) {
        LiushWiFiStrongestMobileWiFi *wifi = [LiushWiFiStrongestMobileWiFi liush_wifistrongest_shared];
        NSString *ssid = nil;
        NSInteger rssi = 0;
        NSInteger channel = 0;
        BOOL connected = [wifi liush_wifistrongest_readCurrentSSID:&ssid rssi:&rssi channel:&channel];
        [LiushWiFiStrongestLog liush_wifistrongest_log:@"心跳：%@ | 上次扫描见到 %ld 个网络",
            connected ? [NSString stringWithFormat:@"%@ %lddBm", ssid, (long)rssi] : @"未连接",
            (long)self.lastScanCount];
    }
    [self liush_wifistrongest_enqueueForced:NO];
}

- (void)liush_wifistrongest_enqueueForced:(BOOL)forced {
    if (self.busy) {
        // 手动扫描不能被丢掉：排到本轮结束后立刻执行。
        if (forced) {
            self.pendingForced = YES;
            [LiushWiFiStrongestLog liush_wifistrongest_log:@"正在判定中，本次手动扫描已排队"];
        }
        return;
    }
    self.busy = YES;
    __weak LiushWiFiStrongestEngine *weakSelf = self;
    dispatch_async(self.queue, ^{
        LiushWiFiStrongestEngine *strongSelf = weakSelf;
        if (!strongSelf) return;
        @autoreleasepool {
            [strongSelf liush_wifistrongest_evaluateForced:forced];
        }
        strongSelf.busy = NO;
        if (strongSelf.pendingForced) {
            strongSelf.pendingForced = NO;
            [strongSelf liush_wifistrongest_enqueueForced:YES];
        }
    });
}

- (BOOL)liush_wifistrongest_screenIsLocked {
    Class lockClass = NSClassFromString(@"SBLockScreenManager");
    if (lockClass && [lockClass respondsToSelector:@selector(sharedInstance)]) {
        id manager = ((id (*)(id, SEL))objc_msgSend)(lockClass, @selector(sharedInstance));
        if ([manager respondsToSelector:@selector(isLockScreenVisible)]) {
            return ((BOOL (*)(id, SEL))objc_msgSend)(manager, @selector(isLockScreenVisible));
        }
    }
    Class stateClass = NSClassFromString(@"SBLockStateAggregator");
    if (stateClass && [stateClass respondsToSelector:@selector(sharedInstance)]) {
        id aggregator = ((id (*)(id, SEL))objc_msgSend)(stateClass, @selector(sharedInstance));
        if ([aggregator respondsToSelector:@selector(lockState)]) {
            return ((NSUInteger (*)(id, SEL))objc_msgSend)(aggregator, @selector(lockState)) != 0;
        }
    }
    return NO;
}

- (BOOL)liush_wifistrongest_cooldownActiveFor:(NSString *)ssid {
    NSDate *until = self.cooldowns[ssid];
    if (!until) return NO;
    if ([until timeIntervalSinceNow] > 0) return YES;
    [self.cooldowns removeObjectForKey:ssid];
    return NO;
}

- (void)liush_wifistrongest_evaluateForced:(BOOL)forced {
    LiushWiFiStrongestConfig *config = [LiushWiFiStrongestConfig liush_wifistrongest_shared];
    if (![config liush_wifistrongest_isEnabled]) {
        // 停用时也留一份快照，面板能明确显示「插件已停用」而不是空白。
        LiushWiFiStrongestMobileWiFi *idle = [LiushWiFiStrongestMobileWiFi liush_wifistrongest_shared];
        NSMutableDictionary *snapshot = [[idle liush_wifistrongest_snapshot] mutableCopy];
        if (snapshot) {
            snapshot[@"note"] = @"插件已停用，未执行扫描";
            liush_wifistrongest_writeSnapshot(snapshot);
        }
        [self liush_wifistrongest_note:@"判定跳过：总开关未启用（设置 → WiFi 择优切换 → 启用插件）"];
        return;
    }

    LiushWiFiStrongestMobileWiFi *wifi = [LiushWiFiStrongestMobileWiFi liush_wifistrongest_shared];
    NSString *currentSSID = nil;
    NSInteger currentRSSI = 0;
    NSInteger currentChannel = 0;
    BOOL connected = [wifi liush_wifistrongest_readCurrentSSID:&currentSSID
                                                       rssi:&currentRSSI
                                                    channel:&currentChannel];

    NSInteger interval = MAX((NSInteger)5, [config liush_wifistrongest_integerForKey:@"scanInterval"
                                                                     defaultValue:20]);
    NSInteger forceThreshold = [config liush_wifistrongest_integerForKey:@"forceThreshold"
                                                         defaultValue:-80];
    NSInteger intervalThreshold = [config liush_wifistrongest_integerForKey:@"intervalThreshold"
                                                            defaultValue:-65];

    if (self.lastSwitch && -[self.lastSwitch timeIntervalSinceNow] < LiushWiFiStrongestPostSwitchQuiet) {
        [self liush_wifistrongest_note:@"判定跳过：刚切换过，静默 20s 等网络稳定"];
        return;
    }
    BOOL urgent = connected && currentRSSI < forceThreshold;
    if (!forced && !urgent) {
        if (connected && currentRSSI > intervalThreshold) {
            [LiushWiFiStrongestLog liush_wifistrongest_verbose:@"信号 %lddBm 高于区间阈值，跳过扫描", (long)currentRSSI];
            return;
        }
        if (self.lastEvaluation &&
            -[self.lastEvaluation timeIntervalSinceNow] < (NSTimeInterval)interval) {
            return;
        }
    }

    if (![wifi liush_wifistrongest_canScan]) {
        [self liush_wifistrongest_note:[NSString stringWithFormat:
            @"判定中止：无法扫描（%@），只更新只读信息", [wifi liush_wifistrongest_diagnostic]]];
        self.lastEvaluation = [NSDate date];
        NSMutableDictionary *snapshot = [[wifi liush_wifistrongest_snapshot] mutableCopy];
        if (snapshot) {
            snapshot[@"note"] = @"无法扫描：缺少 wlan entitlement 或私有符号，以下仅为降级只读信息";
            liush_wifistrongest_writeSnapshot(snapshot);
        }
        return;
    }
    NSInteger previousCount = self.lastScanCount;
    self.lastEvaluation = [NSDate date];

    NSArray<NSDictionary *> *networks = [wifi liush_wifistrongest_scanNetworks];
    self.lastScanCount = (NSInteger)networks.count;
    self.lastReason = nil;  // 真的扫过了，允许下一次如实记录“为什么没切”
    if (forced || networks.count != previousCount) {
        [LiushWiFiStrongestLog liush_wifistrongest_log:@"扫描：%lu 个网络 | 当前 %@ %lddBm 信道 %ld",
            (unsigned long)networks.count, (currentSSID ?: @"未连接"),
            (long)currentRSSI, (long)currentChannel];
    }
    liush_wifistrongest_writeSnapshot([wifi liush_wifistrongest_snapshot]);

    BOOL autoJoin = [config liush_wifistrongest_boolForKey:@"autoJoinWhenDisconnected" defaultValue:NO];
    if (!connected && !autoJoin) {
        [self liush_wifistrongest_note:@"判定跳过：当前没连 WiFi，且「未连接时自动连最强」是关的（详情页仍会更新）"];
        return;
    }

    BOOL prefer5G = [config liush_wifistrongest_prefer5G];
    NSInteger prefer5GBonus = [config liush_wifistrongest_integerForKey:@"prefer5GMaxDiff" defaultValue:15];
    NSInteger minDelta = [config liush_wifistrongest_integerForKey:@"minDelta" defaultValue:8];
    NSArray<NSString *> *whitelist = [config liush_wifistrongest_whitelist];

    double currentScore = connected
        ? liush_wifistrongest_quality(currentRSSI)
            + ((prefer5G && currentChannel > 14) ? prefer5GBonus * 0.5 : 0.0)
        : -1.0;

    NSDictionary *best = nil;
    double bestScore = -1.0;
    for (NSDictionary *network in networks) {
        NSString *candidateSSID = network[@"ssid"];
        if (candidateSSID.length == 0) continue;
        if (connected && [candidateSSID isEqualToString:currentSSID]) continue;
        if (whitelist.count > 0 && ![whitelist containsObject:candidateSSID]) continue;
        if ([self liush_wifistrongest_cooldownActiveFor:candidateSSID]) continue;
        NSInteger candidateRSSI = [network[@"rssi"] integerValue];
        if (candidateRSSI >= 0 || candidateRSSI <= -100) continue;
        double score = liush_wifistrongest_quality(candidateRSSI)
            + ((prefer5G && [network[@"is5g"] boolValue]) ? prefer5GBonus * 0.5 : 0.0);
        if (score > bestScore) {
            bestScore = score;
            best = network;
        }
    }

    if (!best) {
        [self liush_wifistrongest_note:[NSString stringWithFormat:
            @"判定跳过：没有可切换的候选（可见 %lu 个，%lu 个被同 SSID/白名单/冷却过滤掉）",
            (unsigned long)networks.count,
            (unsigned long)MAX((NSInteger)0, (NSInteger)networks.count - (connected ? 1 : 0))]];
        return;
    }
    double improvement = bestScore - currentScore;
    if (improvement < (double)minDelta) {
        [self liush_wifistrongest_note:[NSString stringWithFormat:
            @"判定跳过：最优候选 %@(%lddBm) 只提升 %.1f 分，未达最小差值 %ld",
            best[@"ssid"], (long)[best[@"rssi"] integerValue], improvement, (long)minDelta]];
        return;
    }

    NSString *targetSSID = best[@"ssid"];
    [LiushWiFiStrongestLog liush_wifistrongest_log:@"切换 %@(%lddBm) → %@(%lddBm)，提升 %.1f 分",
        (currentSSID ?: @"未连接"), (long)currentRSSI, targetSSID,
        (long)[best[@"rssi"] integerValue], improvement];
    if ([wifi liush_wifistrongest_associateToSSID:targetSSID]) {
        self.lastSwitch = [NSDate date];
        [LiushWiFiStrongestLog liush_wifistrongest_log:@"切换成功：%@", targetSSID];
    } else {
        NSInteger cooldown = MAX((NSInteger)30, [config liush_wifistrongest_integerForKey:@"failCooldown"
                                                                           defaultValue:300]);
        self.cooldowns[targetSSID] = [NSDate dateWithTimeIntervalSinceNow:(NSTimeInterval)cooldown];
        [LiushWiFiStrongestLog liush_wifistrongest_log:@"切换失败：%@，冷却 %lds", targetSSID, (long)cooldown];
    }
}

@end
