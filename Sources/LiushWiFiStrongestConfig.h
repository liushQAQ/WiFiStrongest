#pragma once

#import <Foundation/Foundation.h>

// 强制扫描通知：面板发 Darwin 通知，SpringBoard 内引擎立即执行一次扫描。
static NSString * const LiushWiFiStrongestForceScanNotification = @"com.liush.wifistrongest.force-scan";

@interface LiushWiFiStrongestConfig : NSObject
+ (instancetype)liush_wifistrongest_shared;
- (BOOL)liush_wifistrongest_isEnabled;
- (id)liush_wifistrongest_valueForKey:(NSString *)key defaultValue:(id)defaultValue;
- (NSInteger)liush_wifistrongest_integerForKey:(NSString *)key defaultValue:(NSInteger)defaultValue;
- (BOOL)liush_wifistrongest_boolForKey:(NSString *)key defaultValue:(BOOL)defaultValue;
- (NSString *)liush_wifistrongest_stringForKey:(NSString *)key defaultValue:(NSString *)defaultValue;
- (BOOL)liush_wifistrongest_debugLog;
- (BOOL)liush_wifistrongest_skipWhenLocked;
- (BOOL)liush_wifistrongest_prefer5G;
- (NSArray<NSString *> *)liush_wifistrongest_whitelist;
- (void)liush_wifistrongest_reload;
@end
