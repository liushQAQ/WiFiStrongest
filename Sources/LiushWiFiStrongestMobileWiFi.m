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
typedef LiushWiFiStrongestNetworkRef (*LiushWiFiStrongestCurrentNetworkFn)(LiushWiFiStrongestDeviceRef);
typedef CFStringRef (*LiushWiFiStrongestSSIDFn)(LiushWiFiStrongestNetworkRef);
typedef int (*LiushWiFiStrongestNetworkIntFn)(LiushWiFiStrongestNetworkRef);
typedef BOOL (*LiushWiFiStrongestNetworkBoolFn)(LiushWiFiStrongestNetworkRef);
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

@implementation LiushWiFiStrongestMobileWiFi {
    void *_handle;
    LiushWiFiStrongestManagerRef _manager;
    LiushWiFiStrongestDeviceRef _device;
    LiushWiFiStrongestCreateFn _create;
    LiushWiFiStrongestGetDeviceFn _getDevice;
    LiushWiFiStrongestCopyDevicesFn _copyDevices;
    LiushWiFiStrongestScanFn _scan;
    LiushWiFiStrongestCopyNetworksFn _copyNetworks;
    LiushWiFiStrongestCurrentNetworkFn _currentNetwork;
    LiushWiFiStrongestSSIDFn _networkSSID;
    LiushWiFiStrongestNetworkIntFn _networkRSSI;
    LiushWiFiStrongestNetworkIntFn _networkChannel;
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
    static const char *const copyNetworksNames[] = {"WiFiManagerClientCopyNetworks",
                                                    "WiFiManagerClientGetNetworks", NULL};
    static const char *const currentNames[] = {"WiFiDeviceClientCopyCurrentNetwork", NULL};
    static const char *const ssidNames[] = {"WiFiNetworkGetSSID", NULL};
    static const char *const rssiNames[] = {"WiFiNetworkGetRSSI", "WiFiNetworkGetScaledRSSI", NULL};
    static const char *const channelNames[] = {"WiFiNetworkGetChannel", NULL};
    static const char *const associateNames[] = {"WiFiDeviceClientAssociateAsync",
                                                 "WiFiDeviceClientAssociate", NULL};

    _create = (LiushWiFiStrongestCreateFn)liush_wifistrongest_resolveSymbol(_handle, createNames);
    _getDevice = (LiushWiFiStrongestGetDeviceFn)liush_wifistrongest_resolveSymbol(_handle, getDeviceNames);
    _copyDevices = (LiushWiFiStrongestCopyDevicesFn)liush_wifistrongest_resolveSymbol(_handle, copyDevicesNames);
    _scan = (LiushWiFiStrongestScanFn)liush_wifistrongest_resolveSymbol(_handle, scanNames);
    _copyNetworks = (LiushWiFiStrongestCopyNetworksFn)liush_wifistrongest_resolveSymbol(_handle, copyNetworksNames);
    _currentNetwork = (LiushWiFiStrongestCurrentNetworkFn)liush_wifistrongest_resolveSymbol(_handle, currentNames);
    _networkSSID = (LiushWiFiStrongestSSIDFn)liush_wifistrongest_resolveSymbol(_handle, ssidNames);
    _networkRSSI = (LiushWiFiStrongestNetworkIntFn)liush_wifistrongest_resolveSymbol(_handle, rssiNames);
    _networkChannel = (LiushWiFiStrongestNetworkIntFn)liush_wifistrongest_resolveSymbol(_handle, channelNames);
    _associate = (LiushWiFiStrongestAssociateFn)liush_wifistrongest_resolveSymbol(_handle, associateNames);

    if (!_create) [_missing addObject:@"WiFiManagerClientCreate"];
    if (!_scan) [_missing addObject:@"WiFiManagerClientScanNetworks"];
    if (!_copyNetworks) [_missing addObject:@"WiFiManagerClientCopyNetworks"];
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
}

- (BOOL)liush_wifistrongest_available {
    return _manager != NULL;
}

- (BOOL)liush_wifistrongest_canScan {
    return _manager != NULL && _scan && _copyNetworks && _networkSSID && _networkRSSI;
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
                if (channel && _networkChannel) *channel = _networkChannel(network);
                return YES;
            }
        }
    }
    return [self liush_wifistrongest_readFallbackSSID:ssid rssi:rssi];
}

- (NSArray<NSDictionary *> *)liush_wifistrongest_scanNetworks {
    _scanned = nil;
    if (![self liush_wifistrongest_canScan]) return @[];
    _scan(_manager);
    NSArray *networks = CFBridgingRelease(_copyNetworks(_manager));
    if (![networks isKindOfClass:[NSArray class]] || networks.count == 0) {
        [LiushWiFiStrongestLog liush_wifistrongest_verbose:@"扫描结果为空"];
        return @[];
    }
    _scanned = networks;
    NSMutableArray<NSDictionary *> *result = [NSMutableArray arrayWithCapacity:networks.count];
    for (id item in networks) {
        LiushWiFiStrongestNetworkRef network = (__bridge LiushWiFiStrongestNetworkRef)item;
        CFStringRef name = _networkSSID(network);
        if (!name || CFGetTypeID(name) != CFStringGetTypeID() || CFStringGetLength(name) == 0) continue;
        NSInteger networkRSSI = _networkRSSI ? _networkRSSI(network) : -100;
        NSInteger networkChannel = _networkChannel ? _networkChannel(network) : 0;
        [result addObject:@{
            @"ssid": (__bridge NSString *)name,
            @"rssi": @(networkRSSI),
            @"channel": @(networkChannel),
            @"is5g": @(networkChannel > 14),
        }];
    }
    return result;
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
