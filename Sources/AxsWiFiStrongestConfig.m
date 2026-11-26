#import "AxsWiFiStrongestConfig.h"
#import "AxsWiFiStrongestPreferences.h"

@interface AxsWiFiStrongestConfig ()
@property (atomic, copy) NSDictionary *snapshot;
@property (nonatomic, strong) dispatch_queue_t reloadQueue;
@end

static void axs_wifistrongest_preferencesDidChange(CFNotificationCenterRef center, void *observer,
                                          CFStringRef name, const void *object, CFDictionaryRef info) {
    AxsWiFiStrongestConfig *config = (__bridge AxsWiFiStrongestConfig *)observer;
    dispatch_async(config.reloadQueue, ^{
        [config axs_wifistrongest_reload];
    });
}

@implementation AxsWiFiStrongestConfig

+ (instancetype)axs_wifistrongest_shared {
    static AxsWiFiStrongestConfig *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _reloadQueue = dispatch_queue_create("com.axs.wifistrongest.preferences", DISPATCH_QUEUE_SERIAL);
        [self axs_wifistrongest_reload];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            (__bridge const void *)self, axs_wifistrongest_preferencesDidChange,
            (__bridge CFStringRef)AxsWiFiStrongestPreferencesChanged, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        // Close the window between the first read and observer registration.
        dispatch_async(_reloadQueue, ^{ [self axs_wifistrongest_reload]; });
    }
    return self;
}

- (void)axs_wifistrongest_reload {
    self.snapshot = axs_wifistrongest_readPreferences();
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:AxsWiFiStrongestPreferencesChanged object:self];
    });
}

- (id)axs_wifistrongest_valueForKey:(NSString *)key defaultValue:(id)defaultValue {
    return self.snapshot[key] ?: defaultValue;
}

- (BOOL)axs_wifistrongest_isEnabled {
    id value = [self axs_wifistrongest_valueForKey:@"enabled" defaultValue:@(NO)];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : NO;
}

- (NSInteger)axs_wifistrongest_integerForKey:(NSString *)key defaultValue:(NSInteger)defaultValue {
    id value = [self axs_wifistrongest_valueForKey:key defaultValue:nil];
    if ([value isKindOfClass:[NSNumber class]]) return [value integerValue];
    if ([value isKindOfClass:[NSString class]]) return [(NSString *)value integerValue];
    return defaultValue;
}

- (BOOL)axs_wifistrongest_boolForKey:(NSString *)key defaultValue:(BOOL)defaultValue {
    id value = [self axs_wifistrongest_valueForKey:key defaultValue:nil];
    if ([value isKindOfClass:[NSNumber class]]) return [value boolValue];
    return defaultValue;
}

- (NSString *)axs_wifistrongest_stringForKey:(NSString *)key defaultValue:(NSString *)defaultValue {
    id value = [self axs_wifistrongest_valueForKey:key defaultValue:nil];
    return [value isKindOfClass:[NSString class]] ? value : defaultValue;
}

- (BOOL)axs_wifistrongest_debugLog {
    return [self axs_wifistrongest_boolForKey:@"debugLog" defaultValue:NO];
}

- (BOOL)axs_wifistrongest_skipWhenLocked {
    return [self axs_wifistrongest_boolForKey:@"skipWhenLocked" defaultValue:YES];
}

- (BOOL)axs_wifistrongest_prefer5G {
    return [self axs_wifistrongest_boolForKey:@"prefer5G" defaultValue:YES];
}

- (NSArray<NSString *> *)axs_wifistrongest_whitelist {
    NSString *raw = [self axs_wifistrongest_stringForKey:@"whitelist" defaultValue:@""];
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (NSString *part in [raw componentsSeparatedByCharactersInSet:
            [NSCharacterSet characterSetWithCharactersInString:@",，;；\n"]]) {
        NSString *trimmed = [part stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) [result addObject:trimmed];
    }
    return result;
}

- (void)dealloc {
    CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                            (__bridge const void *)self);
}

@end
