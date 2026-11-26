#import "LiushWiFiStrongestConfig.h"
#import "LiushWiFiStrongestPreferences.h"

@interface LiushWiFiStrongestConfig ()
@property (atomic, copy) NSDictionary *snapshot;
@property (nonatomic, strong) dispatch_queue_t reloadQueue;
@end

static void liush_wifistrongest_preferencesDidChange(CFNotificationCenterRef center, void *observer,
                                          CFStringRef name, const void *object, CFDictionaryRef info) {
    LiushWiFiStrongestConfig *config = (__bridge LiushWiFiStrongestConfig *)observer;
    dispatch_async(config.reloadQueue, ^{
        [config liush_wifistrongest_reload];
    });
}

@implementation LiushWiFiStrongestConfig

+ (instancetype)liush_wifistrongest_shared {
    static LiushWiFiStrongestConfig *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _reloadQueue = dispatch_queue_create("com.liush.wifistrongest.preferences", DISPATCH_QUEUE_SERIAL);
        [self liush_wifistrongest_reload];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            (__bridge const void *)self, liush_wifistrongest_preferencesDidChange,
            (__bridge CFStringRef)LiushWiFiStrongestPreferencesChanged, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        // Close the window between the first read and observer registration.
        dispatch_async(_reloadQueue, ^{ [self liush_wifistrongest_reload]; });
    }
    return self;
}

- (void)liush_wifistrongest_reload {
    self.snapshot = liush_wifistrongest_readPreferences();
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:LiushWiFiStrongestPreferencesChanged object:self];
    });
}

- (id)liush_wifistrongest_valueForKey:(NSString *)key defaultValue:(id)defaultValue {
    return self.snapshot[key] ?: defaultValue;
}

- (BOOL)liush_wifistrongest_isEnabled {
    id value = [self liush_wifistrongest_valueForKey:@"enabled" defaultValue:@(NO)];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : NO;
}

- (NSInteger)liush_wifistrongest_integerForKey:(NSString *)key defaultValue:(NSInteger)defaultValue {
    id value = [self liush_wifistrongest_valueForKey:key defaultValue:nil];
    if ([value isKindOfClass:[NSNumber class]]) return [value integerValue];
    if ([value isKindOfClass:[NSString class]]) return [(NSString *)value integerValue];
    return defaultValue;
}

- (BOOL)liush_wifistrongest_boolForKey:(NSString *)key defaultValue:(BOOL)defaultValue {
    id value = [self liush_wifistrongest_valueForKey:key defaultValue:nil];
    if ([value isKindOfClass:[NSNumber class]]) return [value boolValue];
    return defaultValue;
}

- (NSString *)liush_wifistrongest_stringForKey:(NSString *)key defaultValue:(NSString *)defaultValue {
    id value = [self liush_wifistrongest_valueForKey:key defaultValue:nil];
    return [value isKindOfClass:[NSString class]] ? value : defaultValue;
}

- (BOOL)liush_wifistrongest_debugLog {
    return [self liush_wifistrongest_boolForKey:@"debugLog" defaultValue:NO];
}

- (BOOL)liush_wifistrongest_skipWhenLocked {
    return [self liush_wifistrongest_boolForKey:@"skipWhenLocked" defaultValue:YES];
}

- (BOOL)liush_wifistrongest_prefer5G {
    return [self liush_wifistrongest_boolForKey:@"prefer5G" defaultValue:YES];
}

- (NSArray<NSString *> *)liush_wifistrongest_whitelist {
    NSString *raw = [self liush_wifistrongest_stringForKey:@"whitelist" defaultValue:@""];
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
