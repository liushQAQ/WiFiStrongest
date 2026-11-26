#import "LiushWiFiStrongestWhitelistController.h"
#import "LiushWiFiStrongestPreferences.h"
#import "LiushWiFiStrongestPaths.h"

// 白名单存在 preferences 的 whitelist 键里，格式是英文逗号分隔的字符串（引擎按逗号/分号/换行切）。
// 这一页只负责增删，最终仍然写回同一个键，保证和引擎读取逻辑一致。
@interface LiushWiFiStrongestWhitelistController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray<NSString *> *entries;
@property (nonatomic, strong) NSArray<NSDictionary *> *scanned;
@end

@implementation LiushWiFiStrongestWhitelistController

// 同样：基类是 PSViewController，表格自己搭。
- (void)loadView {
    UITableView *table = [[UITableView alloc] initWithFrame:CGRectZero
                                                     style:UITableViewStyleInsetGrouped];
    table.dataSource = self;
    table.delegate = self;
    self.view = table;
    self.tableView = table;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"白名单 SSID";
    self.navigationItem.rightBarButtonItem = self.editButtonItem;
    [self liush_wifistrongest_loadAll];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self liush_wifistrongest_loadAll];
}

#pragma mark - 读写

- (void)liush_wifistrongest_loadAll {
    NSString *raw = liush_wifistrongest_readPreferences()[@"whitelist"];
    NSMutableArray<NSString *> *list = [NSMutableArray array];
    if ([raw isKindOfClass:[NSString class]]) {
        for (NSString *part in [raw componentsSeparatedByCharactersInSet:
                [NSCharacterSet characterSetWithCharactersInString:@",，;；\n"]]) {
            NSString *trimmed = [part stringByTrimmingCharactersInSet:
                                 [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length > 0 && ![list containsObject:trimmed]) [list addObject:trimmed];
        }
    }
    self.entries = list;

    NSData *data = [NSData dataWithContentsOfFile:liush_wifistrongest_snapshotPath()];
    NSArray *networks = nil;
    if (data.length > 0) {
        id decoded = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        if ([decoded isKindOfClass:[NSDictionary class]]) {
            id raw = ((NSDictionary *)decoded)[@"networks"];
            if ([raw isKindOfClass:[NSArray class]]) networks = raw;
        }
    }
    NSMutableArray<NSDictionary *> *candidates = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id item in networks) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSString *ssid = item[@"ssid"];
        if (![ssid isKindOfClass:[NSString class]] || ssid.length == 0) continue;
        if ([list containsObject:ssid] || [seen containsObject:ssid]) continue;
        [seen addObject:ssid];
        [candidates addObject:item];
    }
    self.scanned = candidates;
    [self.tableView reloadData];
}

- (void)liush_wifistrongest_save {
    NSString *joined = [self.entries componentsJoinedByString:@","];
    NSError *error = nil;
    if (!liush_wifistrongest_writePreference(@"whitelist", joined, &error)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"保存失败"
            message:error.localizedDescription ?: @"请检查设置文件写入权限。"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)liush_wifistrongest_addSSID:(NSString *)ssid {
    NSString *trimmed = [ssid stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return;
    if ([self.entries containsObject:trimmed]) {
        [self liush_wifistrongest_flashMessage:@"这个网络已经在白名单里了"];
        return;
    }
    [self.entries addObject:trimmed];
    [self liush_wifistrongest_save];
    [self liush_wifistrongest_loadAll];
}

- (void)liush_wifistrongest_flashMessage:(NSString *)text {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
        message:text preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:alert animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [alert dismissViewControllerAnimated:YES completion:nil];
    });
}

- (void)liush_wifistrongest_promptManualInput {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"添加 SSID"
        message:@"输入要加入白名单的 WiFi 名称，区分大小写，需与路由器广播的名称完全一致。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"例如 Home-5G";
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"加入" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf liush_wifistrongest_addSSID:alert.textFields.firstObject.text ?: @""];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return self.entries.count > 0 ? self.entries.count : 1;
    if (section == 1) return self.scanned.count > 0 ? self.scanned.count : 1;
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) {
        return self.entries.count > 0
            ? [NSString stringWithFormat:@"已加入白名单（%lu）", (unsigned long)self.entries.count]
            : @"已加入白名单";
    }
    if (section == 1) return @"扫描到的网络（点击加入）";
    return @"";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return self.entries.count > 0
            ? @"只有名单里的网络会被切换过去。向左滑动可删除；留空则所有扫描到的网络都参与。"
            : @"还没加任何网络。此时插件会把扫描到的所有网络都当候选——包括没存过密码的热点，会连接失败然后进冷却。建议至少加一个自己的 WiFi。";
    }
    if (section == 1) {
        return self.scanned.count > 0
            ? @"列表来自上一次扫描快照。想更新请回到上一页点「立即扫描一次」，或进「WiFi 详情」点右上角刷新。"
            : @"暂无扫描数据。回到上一页点「立即扫描一次」，稍等两秒再进来。";
    }
    return @"也可以手动输入路由器广播的名称（区分大小写）。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"LiushWiFiStrongestWhitelistCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    }
    cell.textLabel.textColor = [UIColor labelColor];
    cell.accessoryType = UITableViewCellAccessoryNone;

    if (indexPath.section == 0) {
        if (self.entries.count == 0) {
            cell.textLabel.text = @"未设置：所有网络都参与";
            cell.detailTextLabel.text = @"建议至少加一个";
            cell.textLabel.textColor = [UIColor secondaryLabelColor];
        } else {
            cell.textLabel.text = self.entries[indexPath.row];
            cell.detailTextLabel.text = @"已在白名单内";
        }
        return cell;
    }

    if (indexPath.section == 1) {
        if (self.scanned.count == 0) {
            cell.textLabel.text = @"暂无数据";
            cell.detailTextLabel.text = @"先去点「立即扫描一次」";
            cell.textLabel.textColor = [UIColor secondaryLabelColor];
            return cell;
        }
        NSDictionary *network = self.scanned[indexPath.row];
        NSInteger rssi = [network[@"rssi"] integerValue];
        cell.textLabel.text = [NSString stringWithFormat:@"＋ %@", network[@"ssid"] ?: @"未知"];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld dBm · %@ · %@",
            (long)rssi,
            network[@"band"] ?: @"未知",
            [network[@"current"] boolValue] ? @"当前已连接" : (network[@"security"] ?: @"未知")];
        cell.textLabel.textColor = [UIColor systemBlueColor];
        return cell;
    }

    cell.textLabel.text = @"添加 SSID（手动输入）…";
    cell.textLabel.textColor = [UIColor systemBlueColor];
    cell.detailTextLabel.text = nil;
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 0 && self.entries.count > 0;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
                                            forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    if (indexPath.row >= (NSInteger)self.entries.count) return;
    [self.entries removeObjectAtIndex:indexPath.row];
    [self liush_wifistrongest_save];
    [self liush_wifistrongest_loadAll];
    if (self.entries.count == 0) [self setEditing:NO animated:YES];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        if (self.entries.count == 0 || indexPath.row >= (NSInteger)self.entries.count) return;
        NSString *ssid = self.entries[indexPath.row];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:ssid
            message:@"要把这个网络从白名单移除吗？" preferredStyle:UIAlertControllerStyleActionSheet];
        __weak typeof(self) weakSelf = self;
        [alert addAction:[UIAlertAction actionWithTitle:@"移除" style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction *action) {
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf.entries removeObject:ssid];
            [strongSelf liush_wifistrongest_save];
            [strongSelf liush_wifistrongest_loadAll];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    if (indexPath.section == 1) {
        if (self.scanned.count == 0 || indexPath.row >= (NSInteger)self.scanned.count) return;
        [self liush_wifistrongest_addSSID:self.scanned[indexPath.row][@"ssid"] ?: @""];
        return;
    }
    [self liush_wifistrongest_promptManualInput];
}

@end
