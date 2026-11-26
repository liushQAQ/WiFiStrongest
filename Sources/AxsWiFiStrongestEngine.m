#import "AxsWiFiStrongestEngine.h"
#import "AxsWiFiStrongestConfig.h"
#import "AxsWiFiStrongestLog.h"
#import "AxsWiFiStrongestMobileWiFi.h"
#import <objc/message.h>

static const NSTimeInterval AxsWiFiStrongestTickInterval = 5.0;
static const NSTimeInterval AxsWiFiStrongestPostSwitchQuiet = 20.0;

// 百分比化信号质量：-100dBm→0，-50dBm 及以上→100。
static double axs_wifistrongest_quality(NSInteger rssi) {
    if (rssi >= -50) return 100.0;
    if (rssi <= -100) return 0.0;
    return (double)(rssi + 100);
}

static void axs_wifistrongest_forceScanCallback(CFNotificationCenterRef center, void *observer,
                                              CFStringRef name, const void *object,
                                              CFDictionaryRef info) {
    AxsWiFiStrongestEngine *engine = (__bridge AxsWiFiStrongestEngine *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [engine axs_wifistrongest_forceScan];
    });
}

@interface AxsWiFiStrongestEngine ()
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *cooldowns;
@property (nonatomic, strong) NSDate *lastEvaluation;
@property (nonatomic, strong) NSDate *lastSwitch;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) BOOL warnedNoScan;
@end

@implementation AxsWiFiStrongestEngine

+ (instancetype)axs_wifistrongest_shared {
    static AxsWiFiStrongestEngine *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.axs.wifistrongest.engine", DISPATCH_QUEUE_SERIAL);
        _cooldowns = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)axs_wifistrongest_start {
    if (self.running) return;
    self.running = YES;
    [AxsWiFiStrongestConfig axs_wifistrongest_shared];
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)self, axs_wifistrongest_forceScanCallback,
        (__bridge CFStringRef)AxsWiFiStrongestForceScanNotification, NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);
    self.timer = [NSTimer scheduledTimerWithTimeInterval:AxsWiFiStrongestTickInterval
                                                  target:self
                                                selector:@selector(axs_wifistrongest_tick:)
                                                userInfo:nil
                                                 repeats:YES];
    self.timer.tolerance = 1.0;
    [AxsWiFiStrongestLog axs_wifistrongest_log:@"引擎启动，静默校验间隔 %.0fs", AxsWiFiStrongestTickInterval];
}

- (void)axs_wifistrongest_reloadTimer {
    // 间隔完全由配置驱动，定时器保持静默节拍，无需重建。
}

- (void)axs_wifistrongest_forceScan {
    [AxsWiFiStrongestLog axs_wifistrongest_log:@"收到手动扫描请求"];
    [self axs_wifistrongest_enqueueForced:YES];
}

- (void)axs_wifistrongest_tick:(NSTimer *)timer {
    AxsWiFiStrongestConfig *config = [AxsWiFiStrongestConfig axs_wifistrongest_shared];
    if (![config axs_wifistrongest_isEnabled]) return;
    if ([config axs_wifistrongest_skipWhenLocked] && [self axs_wifistrongest_screenIsLocked]) return;
    [self axs_wifistrongest_enqueueForced:NO];
}

- (void)axs_wifistrongest_enqueueForced:(BOOL)forced {
    if (self.busy) return;
    self.busy = YES;
    __weak AxsWiFiStrongestEngine *weakSelf = self;
    dispatch_async(self.queue, ^{
        AxsWiFiStrongestEngine *strongSelf = weakSelf;
        if (!strongSelf) return;
        @autoreleasepool {
            [strongSelf axs_wifistrongest_evaluateForced:forced];
        }
        strongSelf.busy = NO;
    });
}

- (BOOL)axs_wifistrongest_screenIsLocked {
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

- (BOOL)axs_wifistrongest_cooldownActiveFor:(NSString *)ssid {
    NSDate *until = self.cooldowns[ssid];
    if (!until) return NO;
    if ([until timeIntervalSinceNow] > 0) return YES;
    [self.cooldowns removeObjectForKey:ssid];
    return NO;
}

- (void)axs_wifistrongest_evaluateForced:(BOOL)forced {
    AxsWiFiStrongestConfig *config = [AxsWiFiStrongestConfig axs_wifistrongest_shared];
    if (![config axs_wifistrongest_isEnabled]) return;

    AxsWiFiStrongestMobileWiFi *wifi = [AxsWiFiStrongestMobileWiFi axs_wifistrongest_shared];
    NSString *currentSSID = nil;
    NSInteger currentRSSI = 0;
    NSInteger currentChannel = 0;
    BOOL connected = [wifi axs_wifistrongest_readCurrentSSID:&currentSSID
                                                       rssi:&currentRSSI
                                                    channel:&currentChannel];

    NSInteger interval = MAX((NSInteger)5, [config axs_wifistrongest_integerForKey:@"scanInterval"
                                                                     defaultValue:20]);
    NSInteger forceThreshold = [config axs_wifistrongest_integerForKey:@"forceThreshold"
                                                         defaultValue:-80];
    NSInteger intervalThreshold = [config axs_wifistrongest_integerForKey:@"intervalThreshold"
                                                            defaultValue:-65];

    if (self.lastSwitch && -[self.lastSwitch timeIntervalSinceNow] < AxsWiFiStrongestPostSwitchQuiet) {
        return;
    }
    BOOL urgent = connected && currentRSSI < forceThreshold;
    if (!forced && !urgent) {
        if (connected && currentRSSI > intervalThreshold) {
            [AxsWiFiStrongestLog axs_wifistrongest_verbose:@"信号 %lddBm 高于区间阈值，跳过扫描", (long)currentRSSI];
            return;
        }
        if (self.lastEvaluation &&
            -[self.lastEvaluation timeIntervalSinceNow] < (NSTimeInterval)interval) {
            return;
        }
    }

    if (![wifi axs_wifistrongest_canScan]) {
        if (!self.warnedNoScan) {
            self.warnedNoScan = YES;
            [AxsWiFiStrongestLog axs_wifistrongest_log:@"无法扫描（%@），仅能做只读判断；请查看日志首行诊断",
                [wifi axs_wifistrongest_diagnostic]];
        }
        self.lastEvaluation = [NSDate date];
        return;
    }
    self.warnedNoScan = NO;
    self.lastEvaluation = [NSDate date];

    NSArray<NSDictionary *> *networks = [wifi axs_wifistrongest_scanNetworks];
    [AxsWiFiStrongestLog axs_wifistrongest_verbose:@"扫描到 %lu 个网络，当前 %@ %lddBm(信道%ld)",
        (unsigned long)networks.count, (currentSSID ?: @"未连接"), (long)currentRSSI, (long)currentChannel];

    BOOL autoJoin = [config axs_wifistrongest_boolForKey:@"autoJoinWhenDisconnected" defaultValue:NO];
    if (!connected && !autoJoin) return;

    BOOL prefer5G = [config axs_wifistrongest_prefer5G];
    NSInteger prefer5GBonus = [config axs_wifistrongest_integerForKey:@"prefer5GMaxDiff" defaultValue:15];
    NSInteger minDelta = [config axs_wifistrongest_integerForKey:@"minDelta" defaultValue:8];
    NSArray<NSString *> *whitelist = [config axs_wifistrongest_whitelist];

    double currentScore = connected
        ? axs_wifistrongest_quality(currentRSSI)
            + ((prefer5G && currentChannel > 14) ? prefer5GBonus * 0.5 : 0.0)
        : -1.0;

    NSDictionary *best = nil;
    double bestScore = -1.0;
    for (NSDictionary *network in networks) {
        NSString *candidateSSID = network[@"ssid"];
        if (candidateSSID.length == 0) continue;
        if (connected && [candidateSSID isEqualToString:currentSSID]) continue;
        if (whitelist.count > 0 && ![whitelist containsObject:candidateSSID]) continue;
        if ([self axs_wifistrongest_cooldownActiveFor:candidateSSID]) continue;
        NSInteger candidateRSSI = [network[@"rssi"] integerValue];
        if (candidateRSSI >= 0 || candidateRSSI <= -100) continue;
        double score = axs_wifistrongest_quality(candidateRSSI)
            + ((prefer5G && [network[@"is5g"] boolValue]) ? prefer5GBonus * 0.5 : 0.0);
        if (score > bestScore) {
            bestScore = score;
            best = network;
        }
    }

    if (!best) {
        [AxsWiFiStrongestLog axs_wifistrongest_verbose:@"没有可切换的候选网络"];
        return;
    }
    double improvement = bestScore - currentScore;
    if (improvement < (double)minDelta) {
        [AxsWiFiStrongestLog axs_wifistrongest_verbose:@"最优候选 %@(%lddBm) 提升 %.1f 分，未达最小差值 %ld",
            best[@"ssid"], (long)[best[@"rssi"] integerValue], improvement, (long)minDelta];
        return;
    }

    NSString *targetSSID = best[@"ssid"];
    [AxsWiFiStrongestLog axs_wifistrongest_log:@"切换 %@(%lddBm) → %@(%lddBm)，提升 %.1f 分",
        (currentSSID ?: @"未连接"), (long)currentRSSI, targetSSID,
        (long)[best[@"rssi"] integerValue], improvement];
    if ([wifi axs_wifistrongest_associateToSSID:targetSSID]) {
        self.lastSwitch = [NSDate date];
        [AxsWiFiStrongestLog axs_wifistrongest_log:@"切换成功：%@", targetSSID];
    } else {
        NSInteger cooldown = MAX((NSInteger)30, [config axs_wifistrongest_integerForKey:@"failCooldown"
                                                                           defaultValue:300]);
        self.cooldowns[targetSSID] = [NSDate dateWithTimeIntervalSinceNow:(NSTimeInterval)cooldown];
        [AxsWiFiStrongestLog axs_wifistrongest_log:@"切换失败：%@，冷却 %lds", targetSSID, (long)cooldown];
    }
}

@end
