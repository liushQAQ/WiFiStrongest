#pragma once

#import <UIKit/UIKit.h>
#import <Preferences/PSViewController.h>

// 白名单管理页：可加任意多条 SSID。
// 数据仍然落在 preferences 的 whitelist 字符串里（逗号分隔），引擎那边不用改。
//
// 同样必须继承 PSViewController，否则 Preferences 一 push 就 unrecognized selector 闪退。
@interface LiushWiFiStrongestWhitelistController : PSViewController
@end
