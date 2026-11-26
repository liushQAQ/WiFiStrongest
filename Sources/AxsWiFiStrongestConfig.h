#pragma once

#import <Foundation/Foundation.h>

// 强制扫描通知：面板发 Darwin 通知，SpringBoard 内引擎立即执行一次扫描。
static NSString * const AxsWiFiStrongestForceScanNotification = @"com.axs.wifistrongest.force-scan";

@interface AxsWiFiStrongestConfig : NSObject
+ (instancetype)axs_wifistrongest_shared;
- (BOOL)axs_wifistrongest_isEnabled;
- (id)axs_wifistrongest_valueForKey:(NSString *)key defaultValue:(id)defaultValue;
- (NSInteger)axs_wifistrongest_integerForKey:(NSString *)key defaultValue:(NSInteger)defaultValue;
- (BOOL)axs_wifistrongest_boolForKey:(NSString *)key defaultValue:(BOOL)defaultValue;
- (NSString *)axs_wifistrongest_stringForKey:(NSString *)key defaultValue:(NSString *)defaultValue;
- (BOOL)axs_wifistrongest_debugLog;
- (BOOL)axs_wifistrongest_skipWhenLocked;
- (BOOL)axs_wifistrongest_prefer5G;
- (NSArray<NSString *> *)axs_wifistrongest_whitelist;
- (void)axs_wifistrongest_reload;
@end
