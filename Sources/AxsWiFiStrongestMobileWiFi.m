#import "AxsWiFiStrongestMobileWiFi.h"
#import "AxsWiFiStrongestLog.h"
#import <CoreFoundation/CoreFoundation.h>
#import <objc/message.h>
#import <dlfcn.h>

typedef void *AxsWiFiStrongestManagerRef;
typedef void *AxsWiFiStrongestDeviceRef;
typedef void *AxsWiFiStrongestNetworkRef;
typedef void (^AxsWiFiStrongestAssocCallback)(int);

typedef AxsWiFiStrongestManagerRef (*AxsWiFiStrongestCreateFn)(CFAllocatorRef, uint32_t);
typedef AxsWiFiStrongestDeviceRef (*AxsWiFiStrongestGetDeviceFn)(AxsWiFiStrongestManagerRef);
typedef CFArrayRef (*AxsWiFiStrongestCopyDevicesFn)(AxsWiFiStrongestManagerRef);
typedef int (*AxsWiFiStrongestScanFn)(AxsWiFiStrongestManagerRef);
typedef CFArrayRef (*AxsWiFiStrongestCopyNetworksFn)(AxsWiFiStrongestManagerRef);
typedef AxsWiFiStrongestNetworkRef (*AxsWiFiStrongestCurrentNetworkFn)(AxsWiFiStrongestDeviceRef);
typedef CFStringRef (*AxsWiFiStrongestSSIDFn)(AxsWiFiStrongestNetworkRef);
typedef int (*AxsWiFiStrongestNetworkIntFn)(AxsWiFiStrongestNetworkRef);
typedef BOOL (*AxsWiFiStrongestNetworkBoolFn)(AxsWiFiStrongestNetworkRef);
typedef void (*AxsWiFiStrongestAssociateFn)(AxsWiFiStrongestDeviceRef,
                                            AxsWiFiStrongestNetworkRef,
                                            AxsWiFiStrongestAssocCallback);

// 私有符号在不同 iOS 版本上改名频繁，按候选名逐个尝试。
static void *axs_wifistrongest_resolveSymbol(void *handle, const char *const *candidates) {
    for (const char *const *name = candidates; *name; name++) {
        void *symbol = handle ? dlsym(handle, *name) : NULL;
        if (symbol) return symbol;
    }
    return NULL;
}

@implementation AxsWiFiStrongestMobileWiFi {
    void *_handle;
    AxsWiFiStrongestManagerRef _manager;
    AxsWiFiStrongestDeviceRef _device;
    AxsWiFiStrongestCreateFn _create;
    AxsWiFiStrongestGetDeviceFn _getDevice;
    AxsWiFiStrongestCopyDevicesFn _copyDevices;
    AxsWiFiStrongestScanFn _scan;
    AxsWiFiStrongestCopyNetworksFn _copyNetworks;
    AxsWiFiStrongestCurrentNetworkFn _currentNetwork;
    AxsWiFiStrongestSSIDFn _networkSSID;
    AxsWiFiStrongestNetworkIntFn _networkRSSI;
    AxsWiFiStrongestNetworkIntFn _networkChannel;
    AxsWiFiStrongestAssociateFn _associate;
    NSArray *_scanned;
    NSMutableArray<NSString *> *_missing;
    BOOL _resolved;
}

+ (instancetype)axs_wifistrongest_shared {
    static AxsWiFiStrongestMobileWiFi *instance;
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
        [self axs_wifistrongest_resolve];
    }
    return self;
}

- (void)axs_wifistrongest_resolve {
    if (_resolved) return;
    _resolved = YES;
    _handle = dlopen("/System/Library/PrivateFrameworks/MobileWiFi.framework/MobileWiFi", RTLD_NOW);
    if (!_handle) {
        [_missing addObject:@"MobileWiFi.framework"];
        [AxsWiFiStrongestLog axs_wifistrongest_log:@"私有框架打不开，降级为 SBWiFiManager 只读模式"];
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

    _create = (AxsWiFiStrongestCreateFn)axs_wifistrongest_resolveSymbol(_handle, createNames);
    _getDevice = (AxsWiFiStrongestGetDeviceFn)axs_wifistrongest_resolveSymbol(_handle, getDeviceNames);
    _copyDevices = (AxsWiFiStrongestCopyDevicesFn)axs_wifistrongest_resolveSymbol(_handle, copyDevicesNames);
    _scan = (AxsWiFiStrongestScanFn)axs_wifistrongest_resolveSymbol(_handle, scanNames);
    _copyNetworks = (AxsWiFiStrongestCopyNetworksFn)axs_wifistrongest_resolveSymbol(_handle, copyNetworksNames);
    _currentNetwork = (AxsWiFiStrongestCurrentNetworkFn)axs_wifistrongest_resolveSymbol(_handle, currentNames);
    _networkSSID = (AxsWiFiStrongestSSIDFn)axs_wifistrongest_resolveSymbol(_handle, ssidNames);
    _networkRSSI = (AxsWiFiStrongestNetworkIntFn)axs_wifistrongest_resolveSymbol(_handle, rssiNames);
    _networkChannel = (AxsWiFiStrongestNetworkIntFn)axs_wifistrongest_resolveSymbol(_handle, channelNames);
    _associate = (AxsWiFiStrongestAssociateFn)axs_wifistrongest_resolveSymbol(_handle, associateNames);

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
            [AxsWiFiStrongestLog axs_wifistrongest_log:@"WiFiManagerClientCreate 返回 NULL，扫描不可用"];
        }
    }
    if (_manager) {
        if (_getDevice) _device = _getDevice(_manager);
        if (!_device && _copyDevices) {
            NSArray *devices = CFBridgingRelease(_copyDevices(_manager));
            if ([devices isKindOfClass:[NSArray class]] && devices.count > 0) {
                _device = (__bridge AxsWiFiStrongestDeviceRef)devices.firstObject;
                CFRetain((__bridge CFTypeRef)devices);
            }
        }
    }
    [AxsWiFiStrongestLog axs_wifistrongest_log:@"私有 API 解析：%@，缺失：%@",
        (_manager ? @"可用" : @"不可用"),
        (_missing.count ? [_missing componentsJoinedByString:@", "] : @"无")];
}

- (BOOL)axs_wifistrongest_available {
    return _manager != NULL;
}

- (BOOL)axs_wifistrongest_canScan {
    return _manager != NULL && _scan && _copyNetworks && _networkSSID && _networkRSSI;
}

- (NSString *)axs_wifistrongest_diagnostic {
    return [NSString stringWithFormat:@"manager=%@ device=%@ 缺失=%@",
            (_manager ? @"是" : @"否"), (_device ? @"是" : @"否"),
            (_missing.count ? [_missing componentsJoinedByString:@" | "] : @"无")];
}

// entitlement 缺失时的只读降级：从 SpringBoard 自己的 SBWiFiManager 取 SSID 与信号格数。
- (BOOL)axs_wifistrongest_readFallbackSSID:(NSString **)ssid rssi:(NSInteger *)rssi {
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

- (BOOL)axs_wifistrongest_readCurrentSSID:(NSString **)ssid
                                     rssi:(NSInteger *)rssi
                                  channel:(NSInteger *)channel {
    if (ssid) *ssid = nil;
    if (rssi) *rssi = 0;
    if (channel) *channel = 0;
    if (_manager && _device && _currentNetwork && _networkSSID) {
        AxsWiFiStrongestNetworkRef network = _currentNetwork(_device);
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
    return [self axs_wifistrongest_readFallbackSSID:ssid rssi:rssi];
}

- (NSArray<NSDictionary *> *)axs_wifistrongest_scanNetworks {
    _scanned = nil;
    if (![self axs_wifistrongest_canScan]) return @[];
    _scan(_manager);
    NSArray *networks = CFBridgingRelease(_copyNetworks(_manager));
    if (![networks isKindOfClass:[NSArray class]] || networks.count == 0) {
        [AxsWiFiStrongestLog axs_wifistrongest_verbose:@"扫描结果为空"];
        return @[];
    }
    _scanned = networks;
    NSMutableArray<NSDictionary *> *result = [NSMutableArray arrayWithCapacity:networks.count];
    for (id item in networks) {
        AxsWiFiStrongestNetworkRef network = (__bridge AxsWiFiStrongestNetworkRef)item;
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

- (BOOL)axs_wifistrongest_associateToSSID:(NSString *)ssid {
    if (ssid.length == 0 || !_device || !_associate || !_networkSSID) return NO;
    AxsWiFiStrongestNetworkRef target = NULL;
    for (id item in _scanned) {
        AxsWiFiStrongestNetworkRef network = (__bridge AxsWiFiStrongestNetworkRef)item;
        CFStringRef name = _networkSSID(network);
        if (!name || CFGetTypeID(name) != CFStringGetTypeID()) continue;
        if ([(__bridge NSString *)name isEqualToString:ssid]) {
            target = network;
            break;
        }
    }
    if (!target) {
        [AxsWiFiStrongestLog axs_wifistrongest_log:@"关联失败：扫描结果里找不到 %@", ssid];
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
        [AxsWiFiStrongestLog axs_wifistrongest_log:@"关联 %@ 超时（20s）", ssid];
        return NO;
    }
    [AxsWiFiStrongestLog axs_wifistrongest_log:@"关联 %@ 返回码 %d", ssid, code];
    return code == 0;
}

@end
