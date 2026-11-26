#pragma once

#import <Foundation/Foundation.h>

@interface LiushWiFiStrongestEngine : NSObject
+ (instancetype)liush_wifistrongest_shared;
- (void)liush_wifistrongest_start;
- (void)liush_wifistrongest_forceScan;      // 忽略间隔，立刻评估一次
- (void)liush_wifistrongest_reloadTimer;    // 配置变更后由引擎自己节流，无需重建
@end
