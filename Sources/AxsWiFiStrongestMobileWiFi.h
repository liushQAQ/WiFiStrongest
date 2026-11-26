#pragma once

#import <Foundation/Foundation.h>

// MobileWiFi 私有框架全部通过 dlopen/dlsym 解析，不参与链接。
// 任一符号缺失只会降级，不会崩溃。
@interface AxsWiFiStrongestMobileWiFi : NSObject
+ (instancetype)axs_wifistrongest_shared;

@property (nonatomic, readonly) BOOL axs_wifistrongest_available;   // 能否创建 WiFiManagerClient
@property (nonatomic, readonly) BOOL axs_wifistrongest_canScan;
@property (nonatomic, readonly, copy) NSString *axs_wifistrongest_diagnostic;

// 读取当前网络；未连接 WiFi 返回 NO。
- (BOOL)axs_wifistrongest_readCurrentSSID:(NSString **)ssid
                                     rssi:(NSInteger *)rssi
                                  channel:(NSInteger *)channel;

// 同步扫描（会阻塞，必须在后台队列调用）。元素为 @{ssid, rssi, channel, is5g}。
- (NSArray<NSDictionary *> *)axs_wifistrongest_scanNetworks;

// 关联到上一次扫描结果中的同名 SSID。
- (BOOL)axs_wifistrongest_associateToSSID:(NSString *)ssid;
@end
