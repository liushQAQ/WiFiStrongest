#pragma once

#import <Foundation/Foundation.h>

@interface AxsWiFiStrongestEngine : NSObject
+ (instancetype)axs_wifistrongest_shared;
- (void)axs_wifistrongest_start;
- (void)axs_wifistrongest_forceScan;      // 忽略间隔，立刻评估一次
- (void)axs_wifistrongest_reloadTimer;    // 配置变更后由引擎自己节流，无需重建
@end
