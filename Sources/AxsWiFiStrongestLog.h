#pragma once

#import <Foundation/Foundation.h>

// 仅落盘到 /var/mobile/Library/Logs，便于面板读取与真机排障。
@interface AxsWiFiStrongestLog : NSObject
+ (NSString *)axs_wifistrongest_path;
+ (void)axs_wifistrongest_log:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
+ (void)axs_wifistrongest_verbose:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
+ (NSString *)axs_wifistrongest_tailWithLines:(NSInteger)lines;
+ (void)axs_wifistrongest_clear;
@end
