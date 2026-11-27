#import "LiushWiFiStrongestRootListController.h"
#import "LiushWiFiStrongestPreferences.h"
#import "LiushWiFiStrongestConfig.h"
#import "LiushWiFiStrongestLog.h"
#import "LiushWiFiStrongestWhitelistController.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>


@interface LiushWiFiStrongestRootListController ()
@property (nonatomic, strong) PSSpecifier *whitelistSpecifier;
@end

@implementation LiushWiFiStrongestRootListController

- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *items = [[self loadSpecifiersFromPlistName:@"LiushWiFiStrongestRoot"
                                                           target:self] mutableCopy];
        // 白名单那行换成可点进去的管理页，右侧显示已加数量。
        for (NSUInteger index = 0; index < items.count; index++) {
            PSSpecifier *specifier = items[index];
            if (![[specifier propertyForKey:@"key"] isEqualToString:@"whitelist"]) continue;
            PSSpecifier *link = [PSSpecifier preferenceSpecifierNamed:@"白名单 SSID（可加多个）"
                                                              target:self
                                                                 set:nil
                                                                 get:@selector(liush_wifistrongest_whitelistSummary:)
                                                              detail:[LiushWiFiStrongestWhitelistController class]
                                                                cell:PSLinkCell
                                                                edit:nil];
            [link setProperty:@"whitelist" forKey:@"key"];
            [link setProperty:[specifier propertyForKey:@"footerText"] forKey:@"footerText"];
            items[index] = link;
            self.whitelistSpecifier = link;
            break;
        }
        [items addObject:[PSSpecifier preferenceSpecifierNamed:@"诊断" target:self
                     set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        [self liush_wifistrongest_addButton:@"运行自检（写日志）" action:@selector(liush_wifistrongest_selfCheck:) to:items];
        [self liush_wifistrongest_addButton:@"立即扫描一次" action:@selector(liush_wifistrongest_forceScanOnce:) to:items];
        [self liush_wifistrongest_addButton:@"查看运行日志" action:@selector(liush_wifistrongest_showLog:) to:items];
        [self liush_wifistrongest_addButton:@"复制日志（发 AI 排障）" action:@selector(liush_wifistrongest_copyLog:) to:items];
        [self liush_wifistrongest_addButton:@"清空日志" action:@selector(liush_wifistrongest_clearLog:) to:items];
        [items addObject:[PSSpecifier preferenceSpecifierNamed:@"关于" target:self
                     set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        [self liush_wifistrongest_addButton:@"项目主页（GitHub）" action:@selector(liush_wifistrongest_openProjectPage:) to:items];
        _specifiers = items;
    }
    return _specifiers;
}

- (void)liush_wifistrongest_addButton:(NSString *)title action:(SEL)action to:(NSMutableArray *)items {
    PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:title target:self
                          set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    item.buttonAction = action;
    [items addObject:item];
}

// 白名单那行右侧的摘要：留空或数量太多时不逐个列名字，避免撑破一行。
- (id)liush_wifistrongest_whitelistSummary:(PSSpecifier *)specifier {
    NSString *raw = liush_wifistrongest_readPreferences()[@"whitelist"];
    NSMutableArray<NSString *> *list = [NSMutableArray array];
    if ([raw isKindOfClass:[NSString class]]) {
        for (NSString *part in [raw componentsSeparatedByCharactersInSet:
                [NSCharacterSet characterSetWithCharactersInString:@",，;；\n"]]) {
            NSString *trimmed = [part stringByTrimmingCharactersInSet:
                                 [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length > 0) [list addObject:trimmed];
        }
    }
    if (list.count == 0) return @"未设置";
    if (list.count == 1) return list.firstObject;
    return [NSString stringWithFormat:@"%lu 个", (unsigned long)list.count];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 从白名单管理页返回后刷新右侧数量。
    if (self.whitelistSpecifier && [self respondsToSelector:@selector(reloadSpecifier:)]) {
        [self reloadSpecifier:self.whitelistSpecifier];
    }
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length == 0) return nil;
    return liush_wifistrongest_readPreferences()[key] ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length == 0) return;
    NSError *error = nil;
    if (!liush_wifistrongest_writePreference(key, value, &error)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"设置未保存"
            message:error.localizedDescription ?: @"请检查配置文件路径和写入权限。"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        [self reloadSpecifiers];
    }
}

- (void)liush_wifistrongest_selfCheck:(id)sender {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)LiushWiFiStrongestSelfCheckNotification, NULL, NULL, true);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已写入自检"
        message:@"自检结果已写进日志，点「复制日志」发我即可。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)liush_wifistrongest_forceScanOnce:(id)sender {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)LiushWiFiStrongestForceScanNotification, NULL, NULL, true);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已发出扫描请求"
        message:@"SpringBoard 收到后评估一次；未连接 WiFi 时插件会跳过扫描（此状态下扫描会触发安全模式），结果写入运行日志。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)liush_wifistrongest_showLog:(id)sender {
    NSString *tail = [LiushWiFiStrongestLog liush_wifistrongest_tailWithLines:60];
    if (tail.length == 0) {
        tail = @"暂无日志。请确认插件已启用，然后点「立即扫描一次」。";
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"运行日志"
        message:tail preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)liush_wifistrongest_copyLog:(id)sender {
    NSString *tail = [LiushWiFiStrongestLog liush_wifistrongest_tailWithLines:120];
    if (tail.length == 0) {
        tail = @"暂无日志。请确认插件已启用，然后点「立即扫描一次」。";
    }
    [UIPasteboard generalPasteboard].string = tail;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已复制到剪贴板"
        message:@"日志已复制，可直接粘贴发送给 AI 排障。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)liush_wifistrongest_clearLog:(id)sender {
    [LiushWiFiStrongestLog liush_wifistrongest_clear];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"日志已清空"
        message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)liush_wifistrongest_openURL:(NSURL *)url fallback:(NSURL *)fallback {
    if (!url) return;
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
        if (success) return;
        if (fallback) {
            [self liush_wifistrongest_openURL:fallback fallback:nil];
        } else {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无法打开链接"
                message:@"请确认已安装对应应用。" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }];
}

- (void)liush_wifistrongest_openProjectPage:(id)sender {
    [self liush_wifistrongest_openURL:[NSURL URLWithString:@"https://github.com/liushQAQ/WiFiStrongest"] fallback:nil];
}


@end
