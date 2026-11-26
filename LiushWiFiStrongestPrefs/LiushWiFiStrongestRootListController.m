#import "LiushWiFiStrongestRootListController.h"
#import "LiushWiFiStrongestPreferences.h"
#import "LiushWiFiStrongestConfig.h"
#import "LiushWiFiStrongestLog.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>


@interface LiushWiFiStrongestRootListController ()
@end

@implementation LiushWiFiStrongestRootListController

- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *items = [[self loadSpecifiersFromPlistName:@"LiushWiFiStrongestRoot"
                                                           target:self] mutableCopy];
        [items addObject:[PSSpecifier preferenceSpecifierNamed:@"诊断" target:self
                     set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        [self liush_wifistrongest_addButton:@"立即扫描一次" action:@selector(liush_wifistrongest_forceScanOnce:) to:items];
        [self liush_wifistrongest_addButton:@"查看运行日志" action:@selector(liush_wifistrongest_showLog:) to:items];
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

- (void)liush_wifistrongest_forceScanOnce:(id)sender {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)LiushWiFiStrongestForceScanNotification, NULL, NULL, true);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已发出扫描请求"
        message:@"SpringBoard 收到请求后会立刻评估一次，结果写入运行日志。"
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
