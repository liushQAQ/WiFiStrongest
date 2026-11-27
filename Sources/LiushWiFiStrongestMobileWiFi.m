#import "LiushWiFiStrongestMobileWiFi.h"
#import "LiushWiFiStrongestLog.h"
#import <CoreFoundation/CoreFoundation.h>
#import <objc/message.h>
#import <dlfcn.h>

typedef void *LiushWiFiStrongestManagerRef;
typedef void *LiushWiFiStrongestDeviceRef;
typedef void *LiushWiFiStrongestNetworkRef;
typedef void (^LiushWiFiStrongestAssocCallback)(int);

typedef LiushWiFiStrongestManagerRef (*LiushWiFiStrongestCreateFn)(CFAllocatorRef, uint32_t);
typedef LiushWiFiStrongestDeviceRef (*LiushWiFiStrongestGetDeviceFn)(LiushWiFiStrongestManagerRef);
typedef CFArrayRef (*LiushWiFiStrongestCopyDevicesFn)(LiushWiFiStrongestManagerRef);
typedef int (*LiushWiFiStrongestScanFn)(LiushWiFiStrongestManagerRef);
typedef CFArrayRef (*LiushWiFiStrongestCopyNetworksFn)(LiushWiFiStrongestManagerRef);
typedef CFArrayRef (*LiushWiFiStrongestCopyAvailableFn)(LiushWiFiStrongestDeviceRef);
typedef void (*LiushWiFiStrongestScanCallback)(LiushWiFiStrongestDeviceRef, CFArrayRef, CFErrorRef, void *);
typedef void (*LiushWiFiStrongestScanAsyncFn)(LiushWiFiStrongestDeviceRef, CFDictionaryRef,
                                             LiushWiFiStrongestScanCallback, void *);
typedef void (*LiushWiFiStrongestScheduleFn)(LiushWiFiStrongestManagerRef, CFRunLoopRef, CFStringRef);
typedef LiushWiFiStrongestNetworkRef (*LiushWiFiStrongestCurrentNetworkFn)(LiushWiFiStrongestDeviceRef);
typedef CFStringRef (*LiushWiFiStrongestSSIDFn)(LiushWiFiStrongestNetworkRef);
typedef int (*LiushWiFiStrongestNetworkIntFn)(LiushWiFiStrongestNetworkRef);
typedef BOOL (*LiushWiFiStrongestNetworkBoolFn)(LiushWiFiStrongestNetworkRef);
typedef CFTypeRef (*LiushWiFiStrongestGetPropertyFn)(LiushWiFiStrongestNetworkRef, CFStringRef);
typedef void (*LiushWiFiStrongestAssociateFn)(LiushWiFiStrongestDeviceRef,
                                            LiushWiFiStrongestNetworkRef,
                                            LiushWiFiStrongestAssocCallback);

// 私有符号在不同 iOS 版本上改名频繁，按候选名逐个尝试。
static void *liush_wifistrongest_resolveSymbol(void *handle, const char *const *candidates) {
    for (const char *const *name = candidates; *name; name++) {
        void *symbol = handle ? dlsym(handle, *name) : NULL;
        if (symbol) return symbol;
    }
    return NULL;
}

// 信号百分比：-100dBm→0，-50dBm 及以上→100。GoodWiFi 的「取消 RSSI 限制」即不做这里的截断。
static NSInteger liush_wifistrongest_pct(NSInteger rssi) {
    if (rssi >= -50) return 100;
    if (rssi <= -100) return 0;
    return rssi + 100;
}

@interface LiushWiFiStrongestMobileWiFi ()
- (NSString *)liush_wifistrongest_bssidFor:(LiushWiFiStrongestNetworkRef)network;
- (NSInteger)liush_wifistrongest_channelFor:(LiushWiFiStrongestNetworkRef)network;
- (NSString *)liush_wifistrongest_securityFor:(LiushWiFiStrongestNetworkRef)network;
- (NSString *)liush_wifistrongest_bandForChannel:(NSInteger)channel;
- (NSDictionary *)liush_wifistrongest_describeNetwork:(LiushWiFiStrongestNetworkRef)network
                                             isCurrent:(BOOL)isCurrent
                                              fallback:(NSDictionary *)fallback;
@end

@implementation LiushWiFiStrongestMobileWiFi {
    void *_handle;
    LiushWiFiStrongestManagerRef _manager;
    LiushWiFiStrongestDeviceRef _device;
    LiushWiFiStrongestCreateFn _create;
    LiushWiFiStrongestGetDeviceFn _getDevice;
    LiushWiFiStrongestCopyDevicesFn _copyDevices;
    LiushWiFiStrongestScanFn _scan;
    LiushWiFiStrongestScanAsyncFn _scanAsync;
    LiushWiFiStrongestCopyAvailableFn _copyAvailable;
    LiushWiFiStrongestScheduleFn _schedule;
    LiushWiFiStrongestCopyNetworksFn _copyNetworks;
    LiushWiFiStrongestCurrentNetworkFn _currentNetwork;
    LiushWiFiStrongestSSIDFn _networkSSID;
    LiushWiFiStrongestNetworkIntFn _networkRSSI;
    LiushWiFiStrongestNetworkIntFn _networkChannel;
    LiushWiFiStrongestGetPropertyFn _getProperty;
    LiushWiFiStrongestSSIDFn _networkBSSID;
    LiushWiFiStrongestNetworkBoolFn _isWEP;
    LiushWiFiStrongestNetworkBoolFn _isWPA;
    LiushWiFiStrongestNetworkBoolFn _isWPA2;
    LiushWiFiStrongestNetworkBoolFn _isWPA3;
    LiushWiFiStrongestNetworkBoolFn _isEAP;
    LiushWiFiStrongestNetworkBoolFn _isSAE;
    LiushWiFiStrongestAssociateFn _associate;
    NSArray *_scanned;
    NSMutableArray<NSString *> *_missing;
    BOOL _resolved;
}

+ (instancetype)liush_wifistrongest_shared {
    static LiushWiFiStrongestMobileWiFi *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _missing = [NSMutableArray array];
        [self liush_wifistrongest_resolve];
    }
    return self;
}

- (void)liush_wifistrongest_resolve {
    if (_resolved) return;
    _resolved = YES;
    _handle = dlopen("/System/Library/PrivateFrameworks/MobileWiFi.framework/MobileWiFi", RTLD_NOW);
    if (!_handle) {
        [_missing addObject:@"MobileWiFi.framework"];
        [LiushWiFiStrongestLog liush_wifistrongest_log:@"私有框架打不开，降级为 SBWiFiManager 只读模式"];
        return;
    }
    static const char *const createNames[] = {"WiFiManagerClientCreate", NULL};
    static const char *const getDeviceNames[] = {"WiFiManagerClientGetDevice", NULL};
    static const char *const copyDevicesNames[] = {"WiFiManagerClientCopyDevices", NULL};
    static const char *const scanNames[] = {"WiFiManagerClientScanNetworks", "WiFiManagerClientScan", NULL};
    static const char *const scanAsyncNames[] = {"WiFiDeviceClientScanAsync", NULL};
    static const char *const copyAvailableNames[] = {"WiFiDeviceClientCopyAvailableNetworks",
                                                     "WiFiDeviceClientCopyAvailableNetworksSync", NULL};
    static const char *const scheduleNames[] = {"WiFiManagerClientScheduleWithRunLoop", NULL};
    static const char *const copyNetworksNames[] = {"WiFiManagerClientCopyNetworks",
                                                    "WiFiManagerClientGetNetworks", NULL};
    static const char *const currentNames[] = {"WiFiDeviceClientCopyCurrentNetwork", NULL};
    static const char *const ssidNames[] = {"WiFiNetworkGetSSID", NULL};
    static const char *const rssiNames[] = {"WiFiNetworkGetRSSI", "WiFiNetworkGetScaledRSSI", NULL};
    static const char *const channelNames[] = {"WiFiNetworkGetChannel", NULL};
    static const char *const propertyNames[] = {"WiFiNetworkGetProperty", NULL};
    static const char *const bssidNames[] = {"WiFiNetworkGetBSSID", NULL};
    static const char *const wepNames[] = {"WiFiNetworkIsWEP", NULL};
    static const char *const wpaNames[] = {"WiFiNetworkIsWPA", NULL};
    static const char *const wpa2Names[] = {"WiFiNetworkIsWPA2", NULL};
    static const char *const wpa3Names[] = {"WiFiNetworkIsWPA3", NULL};
    static const char *const eapNames[] = {"WiFiNetworkIsEAP", NULL};
    static const char *const saeNames[] = {"WiFiNetworkIsSAE", NULL};
    static const char *const associateNames[] = {"WiFiDeviceClientAssociateAsync",
                                                 "WiFiDeviceClientAssociate", NULL};

    _create = (LiushWiFiStrongestCreateFn)liush_wifistrongest_resolveSymbol(_handle, createNames);
    _getDevice = (LiushWiFiStrongestGetDeviceFn)liush_wifistrongest_resolveSymbol(_handle, getDeviceNames);
    _copyDevices = (LiushWiFiStrongestCopyDevicesFn)liush_wifistrongest_resolveSymbol(_handle, copyDevicesNames);
    _scan = (LiushWiFiStrongestScanFn)liush_wifistrongest_resolveSymbol(_handle, scanNames);
    _scanAsync = (LiushWiFiStrongestScanAsyncFn)liush_wifistrongest_resolveSymbol(_handle, scanAsyncNames);
    _copyAvailable = (LiushWiFiStrongestCopyAvailableFn)liush_wifistrongest_resolveSymbol(_handle, copyAvailableNames);
    _schedule = (LiushWiFiStrongestScheduleFn)liush_wifistrongest_resolveSymbol(_handle, scheduleNames);
    _copyNetworks = (LiushWiFiStrongestCopyNetworksFn)liush_wifistrongest_resolveSymbol(_handle, copyNetworksNames);
    _currentNetwork = (LiushWiFiStrongestCurrentNetworkFn)liush_wifistrongest_resolveSymbol(_handle, currentNames);
    _networkSSID = (LiushWiFiStrongestSSIDFn)liush_wifistrongest_resolveSymbol(_handle, ssidNames);
    _networkRSSI = (LiushWiFiStrongestNetworkIntFn)liush_wifistrongest_resolveSymbol(_handle, rssiNames);
    _networkChannel = (LiushWiFiStrongestNetworkIntFn)liush_wifistrongest_resolveSymbol(_handle, channelNames);
    _getProperty = (LiushWiFiStrongestGetPropertyFn)liush_wifistrongest_resolveSymbol(_handle, propertyNames);
    _networkBSSID = (LiushWiFiStrongestSSIDFn)liush_wifistrongest_resolveSymbol(_handle, bssidNames);
    _isWEP = (LiushWiFiStrongestNetworkBoolFn)liush_wifistrongest_resolveSymbol(_handle, wepNames);
    _isWPA = (LiushWiFiStrongestNetworkBoolFn)liush_wifistrongest_resolveSymbol(_handle, wpaNames);
    _isWPA2 = (LiushWiFiStrongestNetworkBoolFn)liush_wifistrongest_resolveSymbol(_handle, wpa2Names);
    _isWPA3 = (LiushWiFiStrongestNetworkBoolFn)liush_wifistrongest_resolveSymbol(_handle, wpa3Names);
    _isEAP = (LiushWiFiStrongestNetworkBoolFn)liush_wifistrongest_resolveSymbol(_handle, eapNames);
    _isSAE = (LiushWiFiStrongestNetworkBoolFn)liush_wifistrongest_resolveSymbol(_handle, saeNames);
    _associate = (LiushWiFiStrongestAssociateFn)liush_wifistrongest_resolveSymbol(_handle, associateNames);

    if (!_create) [_missing addObject:@"WiFiManagerClientCreate"];
    if (!_scanAsync && !_scan) [_missing addObject:@"扫描触发(ScanAsync/ScanNetworks)"];
    if (!_copyAvailable && !_copyNetworks) [_missing addObject:@"结果读取(CopyAvailableNetworks)"];
    if (!_currentNetwork) [_missing addObject:@"WiFiDeviceClientCopyCurrentNetwork"];
    if (!_networkSSID) [_missing addObject:@"WiFiNetworkGetSSID"];
    if (!_networkRSSI) [_missing addObject:@"WiFiNetworkGetRSSI"];
    if (!_associate) [_missing addObject:@"WiFiDeviceClientAssociate*"];

    if (_create) {
        // flags=0 即可；无 com.apple.wlan.authentication 时这里会返回 NULL。
        _manager = _create(kCFAllocatorDefault, 0);
        if (!_manager) {
            [_missing addObject:@"WiFiManagerClient(空):缺少 wlan entitlement"];
            [LiushWiFiStrongestLog liush_wifistrongest_log:@"WiFiManagerClientCreate 返回 NULL，扫描不可用"];
        }
    }
    if (_manager) {
        // 扫描回调走系统 runloop 投递，必须先把 manager 挂上去，否则 ScanAsync 永远不回调。
        if (_schedule) _schedule(_manager, CFRunLoopGetMain(), kCFRunLoopCommonModes);
        if (_getDevice) _device = _getDevice(_manager);
        if (!_device && _copyDevices) {
            NSArray *devices = CFBridgingRelease(_copyDevices(_manager));
            if ([devices isKindOfClass:[NSArray class]] && devices.count > 0) {
                _device = (__bridge LiushWiFiStrongestDeviceRef)devices.firstObject;
                CFRetain((__bridge CFTypeRef)devices);
            }
        }
    }
    [LiushWiFiStrongestLog liush_wifistrongest_log:@"私有 API 解析：%@，缺失：%@",
        (_manager ? @"可用" : @"不可用"),
        (_missing.count ? [_missing componentsJoinedByString:@", "] : @"无")];
    [LiushWiFiStrongestLog liush_wifistrongest_verbose:@"详情字段符号：BSSID=%@ 信道=%@ 加密=%@",
        (_networkBSSID || _getProperty ? @"有" : @"无"),
        (_networkChannel || _getProperty ? @"有" : @"无"),
        (_isWPA2 || _isWPA3 || _isWPA || _isWEP ? @"有" : @"无")];
}

- (BOOL)liush_wifistrongest_available {
    return _manager != NULL;
}

- (BOOL)liush_wifistrongest_canScan {
    BOOL hasScan = (_scanAsync != NULL) || (_scan != NULL);
    BOOL hasResults = (_copyAvailable != NULL) || (_copyNetworks != NULL);
    return _manager != NULL && _device != NULL && hasScan && hasResults
        && _networkSSID != NULL && _networkRSSI != NULL;
}

- (NSString *)liush_wifistrongest_diagnostic {
    return [NSString stringWithFormat:@"manager=%@ device=%@ 缺失=%@",
            (_manager ? @"是" : @"否"), (_device ? @"是" : @"否"),
            (_missing.count ? [_missing componentsJoinedByString:@" | "] : @"无")];
}

// entitlement 缺失时的只读降级：从 SpringBoard 自己的 SBWiFiManager 取 SSID 与信号格数。
- (BOOL)liush_wifistrongest_readFallbackSSID:(NSString **)ssid rssi:(NSInteger *)rssi {
    Class managerClass = NSClassFromString(@"SBWiFiManager");
    if (!managerClass || ![managerClass respondsToSelector:@selector(sharedInstance)]) return NO;
    id manager = ((id (*)(id, SEL))objc_msgSend)(managerClass, @selector(sharedInstance));
    if (!manager) return NO;
    NSString *name = nil;
    if ([manager respondsToSelector:@selector(currentNetworkName)]) {
        name = ((id (*)(id, SEL))objc_msgSend)(manager, @selector(currentNetworkName));
    }
    if (![name isKindOfClass:[NSString class]] || name.length == 0) return NO;
    NSInteger bars = 0;
    if ([manager respondsToSelector:@selector(signalStrengthBars)]) {
        bars = ((NSInteger (*)(id, SEL))objc_msgSend)(manager, @selector(signalStrengthBars));
    }
    if (ssid) *ssid = name;
    if (rssi) *rssi = -100 + (bars > 3 ? 3 : (bars < 0 ? 0 : bars)) * 20;
    return YES;
}

- (BOOL)liush_wifistrongest_readCurrentSSID:(NSString **)ssid
                                     rssi:(NSInteger *)rssi
                                  channel:(NSInteger *)channel {
    if (ssid) *ssid = nil;
    if (rssi) *rssi = 0;
    if (channel) *channel = 0;
    if (_manager && _device && _currentNetwork && _networkSSID) {
        LiushWiFiStrongestNetworkRef network = _currentNetwork(_device);
        if (network) {
            CFStringRef name = _networkSSID(network);
            if (name && CFGetTypeID(name) == CFStringGetTypeID() && CFStringGetLength(name) > 0) {
                if (ssid) *ssid = (__bridge NSString *)name;
                if (rssi && _networkRSSI) *rssi = _networkRSSI(network);
                if (channel) *channel = [self liush_wifistrongest_channelFor:network];
                return YES;
            }
        }
    }
    return [self liush_wifistrongest_readFallbackSSID:ssid rssi:rssi];
}

// 信道：先按 int 读；若返回值不在合法范围（部分系统返回的是 CFNumber 指针），再走 GetProperty("CHANNEL")。
- (NSInteger)liush_wifistrongest_channelFor:(LiushWiFiStrongestNetworkRef)network {
    if (_networkChannel) {
        int value = _networkChannel(network);
        if (value > 0 && value <= 300) return value;
    }
    if (_getProperty) {
        CFTypeRef raw = _getProperty(network, CFSTR("CHANNEL"));
        if (raw && CFGetTypeID(raw) == CFNumberGetTypeID()) {
            int value = 0;
            if (CFNumberGetValue((CFNumberRef)raw, kCFNumberIntType, &value) && value > 0 && value <= 300) {
                return value;
            }
        }
    }
    return 0;
}

- (NSString *)liush_wifistrongest_bssidFor:(LiushWiFiStrongestNetworkRef)network {
    if (_networkBSSID) {
        CFStringRef raw = _networkBSSID(network);
        if (raw && CFGetTypeID(raw) == CFStringGetTypeID() && CFStringGetLength(raw) > 0) {
            return (__bridge NSString *)raw;
        }
    }
    if (_getProperty) {
        CFTypeRef raw = _getProperty(network, CFSTR("BSSID"));
        if (raw && CFGetTypeID(raw) == CFStringGetTypeID() && CFStringGetLength((CFStringRef)raw) > 0) {
            return (__bridge NSString *)raw;
        }
    }
    return nil;
}

- (NSString *)liush_wifistrongest_securityFor:(LiushWiFiStrongestNetworkRef)network {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (_isWPA3 && _isWPA3(network)) [parts addObject:@"WPA3"];
    if (_isSAE && _isSAE(network)) [parts addObject:@"SAE"];
    if (_isWPA2 && _isWPA2(network)) [parts addObject:@"WPA2"];
    if (_isWPA && _isWPA(network)) [parts addObject:@"WPA"];
    if (_isWEP && _isWEP(network)) [parts addObject:@"WEP"];
    if (_isEAP && _isEAP(network)) [parts addObject:@"802.1X"];
    if (parts.count == 0) return @"开放/未知";
    return [parts componentsJoinedByString:@"+"];
}

- (NSString *)liush_wifistrongest_bandForChannel:(NSInteger)channel {
    if (channel <= 0) return @"未知";
    if (channel <= 14) return @"2.4GHz";
    if (channel <= 196) return @"5GHz";
    return @"5/6GHz";
}

- (NSDictionary *)liush_wifistrongest_describeNetwork:(LiushWiFiStrongestNetworkRef)network
                                             isCurrent:(BOOL)isCurrent
                                              fallback:(NSDictionary *)fallback {
    NSString *ssid = fallback[@"ssid"];
    if (ssid.length == 0) return @{};
    NSInteger rssi = [fallback[@"rssi"] integerValue];
    NSInteger channel = [fallback[@"channel"] integerValue];
    NSString *bssid = [self liush_wifistrongest_bssidFor:network];
    NSString *security = [self liush_wifistrongest_securityFor:network];
    NSInteger pct = liush_wifistrongest_pct(rssi);
    return @{
        @"ssid": ssid,
        @"bssid": bssid.length ? bssid : @"未知",
        @"rssi": @(rssi),
        @"pct": @(pct),
        @"channel": @(channel),
        @"band": [self liush_wifistrongest_bandForChannel:channel],
        @"security": security,
        @"is5g": @(channel > 14),
        @"current": @(isCurrent),
    };
}

// 新系统的扫描入口：WiFiDeviceClientScanAsync(device, options, callback, token)。
// 关键：回调的第二个参数才是现场扫描结果（附近真实存在的网络）。
// CopyAvailableNetworks 拿到的是「记忆过的已知网络」缓存，不是现场结果——
// 实测 290 个全是连过的 SSID，周围不存在的也在里面，只能做兜底，不能当扫描结果。
static NSMutableArray *liush_wifistrongest_liveResults;
static void liush_wifistrongest_scanCallback(LiushWiFiStrongestDeviceRef device, CFArrayRef results,
                                             CFErrorRef error, void *token) {
    dispatch_semaphore_t sem = (__bridge dispatch_semaphore_t)token;
    NSMutableArray *live = [NSMutableArray array];
    if (results) {
        // CFBridgingRelease：回调给的数组遵循 Get 规则，直接移交 ARC 持有。
        NSArray *bridged = CFBridgingRelease(results);
        if ([bridged isKindOfClass:[NSArray class]]) [live addObjectsFromArray:bridged];
    }
    @synchronized([LiushWiFiStrongestMobileWiFi class]) {
        liush_wifistrongest_liveResults = live;
    }
    if (sem) dispatch_semaphore_signal(sem);
}

- (BOOL)liush_wifistrongest_triggerScan {
    if (_scanAsync) {
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        _scanAsync(_device, (__bridge CFDictionaryRef)@{},
                   liush_wifistrongest_scanCallback, (__bridge void *)sem);
        long waited = dispatch_semaphore_wait(sem,
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)));
        if (waited != 0) {
            [LiushWiFiStrongestLog liush_wifistrongest_log:@"主动扫描等回调超时(6s)，改用已知网络缓存"];
            return NO;
        }
        return YES;
    }
    if (_scan) {
        _scan(_manager);
        return YES;
    }
    return NO;
}

// 结果来源：现场回调结果优先；只有回调为空/超时才退回已知网络缓存，并在日志注明。
- (NSArray *)liush_wifistrongest_resultNetworks {
    @synchronized([LiushWiFiStrongestMobileWiFi class]) {
        if (liush_wifistrongest_liveResults.count > 0) return liush_wifistrongest_liveResults;
    }
    if (_copyAvailable) {
        NSArray *networks = CFBridgingRelease(_copyAvailable(_device));
        if ([networks isKindOfClass:[NSArray class]] && networks.count > 0) {
            [LiushWiFiStrongestLog liush_wifistrongest_log:
                @"现场结果为空，改用已知网络缓存 %lu 个（可能含不在附近的网络）",
                (unsigned long)networks.count];
            return networks;
        }
    }
    if (_copyNetworks) {
        NSArray *networks = CFBridgingRelease(_copyNetworks(_manager));
        if ([networks isKindOfClass:[NSArray class]]) return networks;
    }
    return @[];
}

- (NSArray<NSDictionary *> *)liush_wifistrongest_scanNetworks {
    _scanned = nil;
    if (![self liush_wifistrongest_canScan]) return @[];
    BOOL triggered = [self liush_wifistrongest_triggerScan];
    NSArray *networks = [self liush_wifistrongest_resultNetworks];
    if (![networks isKindOfClass:[NSArray class]] || networks.count == 0) {
        [LiushWiFiStrongestLog liush_wifistrongest_log:
            triggered ? @"扫描已触发但结果为空" : @"无法触发扫描且缓存为空"];
        return @[];
    }
    _scanned = networks;
    NSMutableArray<NSDictionary *> *result = [NSMutableArray arrayWithCapacity:networks.count];
    for (id item in networks) {
        LiushWiFiStrongestNetworkRef network = (__bridge LiushWiFiStrongestNetworkRef)item;
        CFStringRef name = _networkSSID(network);
        if (!name || CFGetTypeID(name) != CFStringGetTypeID() || CFStringGetLength(name) == 0) continue;
        NSInteger networkRSSI = _networkRSSI ? _networkRSSI(network) : -100;
        NSInteger networkChannel = [self liush_wifistrongest_channelFor:network];
        [result addObject:@{
            @"ssid": (__bridge NSString *)name,
            @"rssi": @(networkRSSI),
            @"channel": @(networkChannel),
            @"is5g": @(networkChannel > 14),
        }];
    }
    return result;
}

- (NSDictionary<NSString *, id> *)liush_wifistrongest_snapshot {
    NSString *currentSSID = nil;
    NSInteger currentRSSI = 0;
    NSInteger currentChannel = 0;
    BOOL connected = [self liush_wifistrongest_readCurrentSSID:&currentSSID
                                                          rssi:&currentRSSI
                                                       channel:&currentChannel];

    NSMutableDictionary *current = [NSMutableDictionary dictionary];
    if (connected) {
        NSString *bssid = nil;
        NSString *security = @"未知";
        if (_manager && _device && _currentNetwork) {
            LiushWiFiStrongestNetworkRef network = _currentNetwork(_device);
            if (network) {
                bssid = [self liush_wifistrongest_bssidFor:network];
                security = [self liush_wifistrongest_securityFor:network];
            }
        }
        current[@"ssid"] = currentSSID ?: @"";
        current[@"bssid"] = bssid.length ? bssid : @"未知";
        current[@"rssi"] = @(currentRSSI);
        current[@"pct"] = @(liush_wifistrongest_pct(currentRSSI));
        current[@"channel"] = @(currentChannel);
        current[@"band"] = [self liush_wifistrongest_bandForChannel:currentChannel];
        current[@"security"] = security;
    }

    NSMutableArray<NSDictionary *> *networks = [NSMutableArray array];
    for (id item in _scanned) {
        LiushWiFiStrongestNetworkRef network = (__bridge LiushWiFiStrongestNetworkRef)item;
        CFStringRef name = _networkSSID ? _networkSSID(network) : NULL;
        if (!name || CFGetTypeID(name) != CFStringGetTypeID() || CFStringGetLength(name) == 0) continue;
        NSString *ssid = (__bridge NSString *)name;
        NSInteger rssi = _networkRSSI ? _networkRSSI(network) : -100;
        NSInteger channel = [self liush_wifistrongest_channelFor:network];
        NSDictionary *described = [self liush_wifistrongest_describeNetwork:network
                                                                  isCurrent:(currentSSID &&
                                                                             [ssid isEqualToString:currentSSID])
                                                                   fallback:@{@"ssid": ssid,
                                                                              @"rssi": @(rssi),
                                                                              @"channel": @(channel)}];
        if (described.count) [networks addObject:described];
    }
    [networks sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        return [right[@"rssi"] compare:left[@"rssi"]];
    }];

    return @{
        @"timestamp": @([[NSDate date] timeIntervalSince1970]),
        @"available": @(self.liush_wifistrongest_available),
        @"canScan": @([self liush_wifistrongest_canScan]),
        @"diagnostic": self.liush_wifistrongest_diagnostic,
        @"current": current,
        @"networks": networks,
    };
}

- (BOOL)liush_wifistrongest_associateToSSID:(NSString *)ssid {
    if (ssid.length == 0 || !_device || !_associate || !_networkSSID) return NO;
    LiushWiFiStrongestNetworkRef target = NULL;
    for (id item in _scanned) {
        LiushWiFiStrongestNetworkRef network = (__bridge LiushWiFiStrongestNetworkRef)item;
        CFStringRef name = _networkSSID(network);
        if (!name || CFGetTypeID(name) != CFStringGetTypeID()) continue;
        if ([(__bridge NSString *)name isEqualToString:ssid]) {
            target = network;
            break;
        }
    }
    if (!target) {
        [LiushWiFiStrongestLog liush_wifistrongest_log:@"关联失败：扫描结果里找不到 %@", ssid];
        return NO;
    }
    __block int code = -1;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    _associate(_device, target, ^(int result) {
        code = result;
        dispatch_semaphore_signal(semaphore);
    });
    long waited = dispatch_semaphore_wait(semaphore,
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC)));
    if (waited != 0) {
        [LiushWiFiStrongestLog liush_wifistrongest_log:@"关联 %@ 超时（20s）", ssid];
        return NO;
    }
    [LiushWiFiStrongestLog liush_wifistrongest_log:@"关联 %@ 返回码 %d", ssid, code];
    return code == 0;
}

@end
