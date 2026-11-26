#pragma once

#import <Foundation/Foundation.h>

// MobileWiFi 私有框架全部通过 dlopen/dlsym 解析，不参与链接。
// 任一符号缺失只会降级，不会崩溃。
@interface LiushWiFiStrongestMobileWiFi : NSObject
+ (instancetype)liush_wifistrongest_shared;

@property (nonatomic, readonly) BOOL liush_wifistrongest_available;   // 能否创建 WiFiManagerClient
@property (nonatomic, readonly) BOOL liush_wifistrongest_canScan;
@property (nonatomic, readonly, copy) NSString *liush_wifistrongest_diagnostic;

// 读取当前网络；未连接 WiFi 返回 NO。
- (BOOL)liush_wifistrongest_readCurrentSSID:(NSString **)ssid
                                     rssi:(NSInteger *)rssi
                                  channel:(NSInteger *)channel;

// 同步扫描（会阻塞，必须在后台队列调用）。元素为 @{ssid, rssi, channel, is5g}。
- (NSArray<NSDictionary *> *)liush_wifistrongest_scanNetworks;

// 关联到上一次扫描结果中的同名 SSID。
- (BOOL)liush_wifistrongest_associateToSSID:(NSString *)ssid;

// GoodWiFi 风格详情快照：当前连接 + 上一次扫描到的全部网络
// （含 BSSID / 信道 / 频段 / 加密方式 / 信号百分比，RSSI 不做任何限幅）。
// 不触发新扫描，直接复用缓存；引擎落盘给设置面板展示。
- (NSDictionary<NSString *, id> *)liush_wifistrongest_snapshot;
@end
