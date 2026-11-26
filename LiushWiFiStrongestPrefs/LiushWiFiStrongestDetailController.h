#pragma once

#import <UIKit/UIKit.h>
#import <Preferences/PSViewController.h>

// 「WiFi 详情」页：展示 SpringBoard 侧扫描快照（SSID / BSSID / 信道 / 频段 / 加密方式 / RSSI / 百分比）。
// 面板进程没有 wlan entitlement，所以不自己扫描，只读快照文件；点右上角刷新会通知 SpringBoard 立刻扫一次。
//
// 必须继承 PSViewController：Preferences 打开二级页时会发送 setSpecifier: / setRootController: /
// setParentController: / initForContentSize:，纯 UITableViewController 没有这些方法，点进去必崩。
@interface LiushWiFiStrongestDetailController : PSViewController <UITableViewDataSource, UITableViewDelegate>
@end
