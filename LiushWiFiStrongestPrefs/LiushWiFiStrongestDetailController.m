#import "LiushWiFiStrongestDetailController.h"
#import "LiushWiFiStrongestConfig.h"
#import "LiushWiFiStrongestPaths.h"
#import "LiushWiFiStrongestPreferences.h"

// GoodWiFi 那套能力的数据来源是 SpringBoard 侧的扫描快照（JSON），
// Preferences 进程既没有 wlan entitlement 也没有扫描权限，所以这里只读文件、不发扫描。
@interface LiushWiFiStrongestDetailController ()
@property (nonatomic, strong) NSDictionary *snapshot;
@property (nonatomic, strong) NSArray<NSDictionary *> *networks;
@property (nonatomic, assign) BOOL refreshing;
@end

@implementation LiushWiFiStrongestDetailController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    return self;
}

// PSListController 在部分系统版本上会按 PSViewController 的约定调用这两个方法，
// 这里给出无害实现，避免因为“unrecognized selector”把设置 App 打崩。
- (instancetype)initWithSpecifier:(id)specifier {
    return [self initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)setSpecifier:(id)specifier {
    (void)specifier;
}

- (id)specifier {
    return nil;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"WiFi 详情";
    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                            target:self
                                                                            action:@selector(liush_wifistrongest_refresh:)];
    self.navigationItem.rightBarButtonItem = refresh;
    [self liush_wifistrongest_loadSnapshot];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self liush_wifistrongest_loadSnapshot];
}

#pragma mark - 数据

- (void)liush_wifistrongest_loadSnapshot {
    NSString *path = liush_wifistrongest_snapshotPath();
    NSData *data = path.length ? [NSData dataWithContentsOfFile:path] : nil;
    NSDictionary *snapshot = nil;
    if (data.length > 0) {
        id decoded = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        if ([decoded isKindOfClass:[NSDictionary class]]) snapshot = decoded;
    }
    self.snapshot = snapshot ?: @{};

    BOOL showWeak = YES;
    id weakValue = liush_wifistrongest_readPreferences()[@"showWeakNetworks"];
    if ([weakValue isKindOfClass:[NSNumber class]]) showWeak = [weakValue boolValue];

    NSArray *raw = snapshot[@"networks"];
    NSMutableArray<NSDictionary *> *list = [NSMutableArray array];
    if ([raw isKindOfClass:[NSArray class]]) {
        for (id item in raw) {
            if (![item isKindOfClass:[NSDictionary class]]) continue;
            NSInteger rssi = [item[@"rssi"] integerValue];
            // 关闭「显示弱信号网络」时隐藏 -85dBm 以下的 AP，相当于 iOS 默认的 RSSI 限制。
            if (!showWeak && rssi < -85) continue;
            [list addObject:item];
        }
    }
    self.networks = list;
    [self.tableView reloadData];
}

- (void)liush_wifistrongest_refresh:(id)sender {
    if (self.refreshing) return;
    self.refreshing = YES;
    self.navigationItem.rightBarButtonItem.enabled = NO;
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)LiushWiFiStrongestForceScanNotification, NULL, NULL, true);
    __weak typeof(self) weakSelf = self;
    // 扫描是异步的，给它一点时间落盘再读。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.refreshing = NO;
        strongSelf.navigationItem.rightBarButtonItem.enabled = YES;
        [strongSelf liush_wifistrongest_loadSnapshot];
    });
}

#pragma mark - 展示辅助

- (UIColor *)liush_wifistrongest_colorForPercent:(NSInteger)pct {
    if (pct >= 70) return [UIColor systemGreenColor];
    if (pct >= 40) return [UIColor systemOrangeColor];
    return [UIColor systemRedColor];
}

- (NSString *)liush_wifistrongest_timeString:(NSTimeInterval)stamp {
    if (stamp <= 0) return @"从未扫描";
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"MM-dd HH:mm:ss";
    return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:stamp]];
}

- (NSString *)liush_wifistrongest_describe:(NSDictionary *)network {
    NSInteger rssi = [network[@"rssi"] integerValue];
    NSInteger pct = network[@"pct"] ? [network[@"pct"] integerValue] : (rssi + 100);
    NSInteger channel = [network[@"channel"] integerValue];
    NSString *band = network[@"band"] ?: @"未知";
    NSString *security = network[@"security"] ?: @"未知";
    NSString *channelText = channel > 0
        ? [NSString stringWithFormat:@"信道 %ld（%@）", (long)channel, band]
        : band;
    return [NSString stringWithFormat:@"%@ · %ld dBm · %ld%% · %@ · %@",
            network[@"bssid"] ?: @"未知", (long)rssi, (long)pct, channelText, security];
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 4;
    return self.networks.count > 0 ? self.networks.count : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"当前状态";
    if (self.networks.count == 0) return @"附近网络";
    return [NSString stringWithFormat:@"附近网络（%lu）", (unsigned long)self.networks.count];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        NSString *note = self.snapshot[@"note"];
        if ([note isKindOfClass:[NSString class]] && note.length > 0) return note;
        return @"数据由 SpringBoard 侧扫描后落盘，面板只读不扫描。想立刻更新点右上角刷新。";
    }
    if (self.networks.count == 0) {
        return @"暂无扫描结果。请回到上一页点「立即扫描一次」，或点右上角刷新；若日志显示私有 API 不可用，说明当前进程缺少 wlan entitlement。";
    }
    return @"点按任意一行可复制该网络的完整信息（发给 AI 排障用）。RSSI 为原始值，不做 iOS 默认限幅。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"LiushWiFiStrongestDetailCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
        cell.detailTextLabel.numberOfLines = 2;
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
    }
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];

    if (indexPath.section == 0) {
        NSDictionary *current = [self.snapshot[@"current"] isKindOfClass:[NSDictionary class]]
            ? self.snapshot[@"current"] : nil;
        NSString *currentSSID = [current[@"ssid"] isKindOfClass:[NSString class]] ? current[@"ssid"] : nil;
        BOOL connected = currentSSID.length > 0;
        switch (indexPath.row) {
            case 0: {
                cell.textLabel.text = connected
                    ? [NSString stringWithFormat:@"当前：%@", currentSSID]
                    : @"当前：未连接 WiFi";
                if (connected) {
                    NSInteger pct = [current[@"pct"] integerValue];
                    cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld dBm · %ld%% · 信道 %@（%@）· %@",
                        (long)[current[@"rssi"] integerValue], (long)pct,
                        current[@"channel"], current[@"band"] ?: @"未知", current[@"security"] ?: @"未知"];
                    cell.detailTextLabel.textColor = [self liush_wifistrongest_colorForPercent:pct];
                } else {
                    cell.detailTextLabel.text = @"可在上一页开启「未连接时自动连最强」";
                }
                break;
            }
            case 1: {
                cell.textLabel.text = @"当前 AP 的 MAC";
                cell.detailTextLabel.text = connected ? (current[@"bssid"] ?: @"未知") : @"—";
                break;
            }
            case 2: {
                BOOL canScan = [self.snapshot[@"canScan"] boolValue];
                cell.textLabel.text = canScan ? @"扫描能力：可用" : @"扫描能力：不可用（只读降级）";
                cell.textLabel.textColor = canScan ? [UIColor labelColor] : [UIColor systemRedColor];
                cell.detailTextLabel.text = self.snapshot[@"diagnostic"] ?: @"无诊断信息";
                break;
            }
            default: {
                NSTimeInterval stamp = [self.snapshot[@"timestamp"] doubleValue];
                cell.textLabel.text = [NSString stringWithFormat:@"上次扫描：%@",
                                       [self liush_wifistrongest_timeString:stamp]];
                cell.detailTextLabel.text = stamp > 0
                    ? [NSString stringWithFormat:@"本轮共 %lu 个网络", (unsigned long)self.networks.count]
                    : @"还没有扫描记录";
                break;
            }
        }
        return cell;
    }

    if (self.networks.count == 0) {
        cell.textLabel.text = @"暂无数据";
        cell.detailTextLabel.text = @"点右上角刷新";
        return cell;
    }

    NSDictionary *network = self.networks[indexPath.row];
    BOOL isCurrent = [network[@"current"] boolValue];
    cell.textLabel.text = isCurrent
        ? [NSString stringWithFormat:@"● %@", network[@"ssid"]]
        : (network[@"ssid"] ?: @"未知");
    cell.detailTextLabel.text = [self liush_wifistrongest_describe:network];
    NSInteger pct = network[@"pct"] ? [network[@"pct"] integerValue] : ([network[@"rssi"] integerValue] + 100);
    cell.detailTextLabel.textColor = [self liush_wifistrongest_colorForPercent:pct];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 1 || self.networks.count == 0) return;
    NSDictionary *network = self.networks[indexPath.row];
    NSString *text = [NSString stringWithFormat:@"SSID: %@\nMAC: %@\n%@%@",
                      network[@"ssid"] ?: @"未知",
                      network[@"bssid"] ?: @"未知",
                      [self liush_wifistrongest_describe:network],
                      [network[@"current"] boolValue] ? @"\n（当前已连接）" : @""];
    [UIPasteboard generalPasteboard].string = text;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已复制"
        message:text preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
