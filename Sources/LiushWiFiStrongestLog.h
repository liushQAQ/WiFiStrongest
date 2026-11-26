#pragma once

#import <Foundation/Foundation.h>

// 仅落盘到 /var/mobile/Library/Logs，便于面板读取与真机排障。
@interface LiushWiFiStrongestLog : NSObject
+ (NSString *)liush_wifistrongest_path;
+ (void)liush_wifistrongest_log:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
+ (void)liush_wifistrongest_verbose:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
+ (NSString *)liush_wifistrongest_tailWithLines:(NSInteger)lines;
+ (void)liush_wifistrongest_clear;
@end
