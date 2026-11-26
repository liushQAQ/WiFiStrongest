#import "AxsWiFiStrongestRootListController.h"
#import "AxsWiFiStrongestPreferences.h"
#import "AxsWiFiStrongestConfig.h"
#import "AxsWiFiStrongestLog.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>


@interface AxsWiFiStrongestRootListController ()
@end

@implementation AxsWiFiStrongestRootListController

- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *items = [[self loadSpecifiersFromPlistName:@"AxsWiFiStrongestRoot"
                                                           target:self] mutableCopy];
        [items addObject:[PSSpecifier preferenceSpecifierNamed:@"诊断" target:self
                     set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        [self axs_wifistrongest_addButton:@"立即扫描一次" action:@selector(axs_wifistrongest_forceScanOnce:) to:items];
        [self axs_wifistrongest_addButton:@"查看运行日志" action:@selector(axs_wifistrongest_showLog:) to:items];
        [self axs_wifistrongest_addButton:@"清空日志" action:@selector(axs_wifistrongest_clearLog:) to:items];
        [items addObject:[PSSpecifier preferenceSpecifierNamed:@"关于我们" target:self
                     set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        [self axs_wifistrongest_addButton:@"Sileo 越狱源" action:@selector(axs_wifistrongest_openRepository:) to:items];
        [self axs_wifistrongest_addButton:@"TG分享频道" action:@selector(axs_wifistrongest_openTelegram:) to:items];
        [self axs_wifistrongest_addButton:@"QQ交流群组" action:@selector(axs_wifistrongest_openQQ:) to:items];
        _specifiers = items;
    }
    return _specifiers;
}

- (void)axs_wifistrongest_addButton:(NSString *)title action:(SEL)action to:(NSMutableArray *)items {
    PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:title target:self
                          set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    item.buttonAction = action;
    [items addObject:item];
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length == 0) return nil;
    return axs_wifistrongest_readPreferences()[key] ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length == 0) return;
    NSError *error = nil;
    if (!axs_wifistrongest_writePreference(key, value, &error)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"设置未保存"
            message:error.localizedDescription ?: @"请检查配置文件路径和写入权限。"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        [self reloadSpecifiers];
    }
}

- (void)axs_wifistrongest_forceScanOnce:(id)sender {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)AxsWiFiStrongestForceScanNotification, NULL, NULL, true);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已发出扫描请求"
        message:@"SpringBoard 收到请求后会立刻评估一次，结果写入运行日志。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)axs_wifistrongest_showLog:(id)sender {
    NSString *tail = [AxsWiFiStrongestLog axs_wifistrongest_tailWithLines:60];
    if (tail.length == 0) {
        tail = @"暂无日志。请确认插件已启用，然后点「立即扫描一次」。";
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"运行日志"
        message:tail preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)axs_wifistrongest_clearLog:(id)sender {
    [AxsWiFiStrongestLog axs_wifistrongest_clear];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"日志已清空"
        message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)axs_wifistrongest_openURL:(NSURL *)url fallback:(NSURL *)fallback {
    if (!url) return;
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
        if (success) return;
        if (fallback) {
            [self axs_wifistrongest_openURL:fallback fallback:nil];
        } else {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无法打开链接"
                message:@"请确认已安装对应应用。" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }];
}

- (void)axs_wifistrongest_openRepository:(id)sender {
    NSString *source = @"https://axs66.github.io/pro";
    // Encode the entire URL as a path component, including its own delimiters.
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
                              @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    NSString *encoded = [source stringByAddingPercentEncodingWithAllowedCharacters:allowed];
    NSURL *primary = [NSURL URLWithString:[@"sileo://source/" stringByAppendingString:encoded]];
    [self axs_wifistrongest_openURL:primary fallback:[NSURL URLWithString:source]];
}

- (void)axs_wifistrongest_openTelegram:(id)sender {
    [self axs_wifistrongest_openURL:[NSURL URLWithString:@"tg://resolve?domain=wxfx8"]
                   fallback:[NSURL URLWithString:@"https://t.me/wxfx8"]];
}

- (void)axs_wifistrongest_openQQ:(id)sender {
    [self axs_wifistrongest_openURL:[NSURL URLWithString:@"mqqapi://card/show_pslcard?src_type=internal&version=1&uin=678055716&card_type=group&source=qrcode"] fallback:nil];
}


@end
