# LiushWiFiStrongest · WiFi 择优切换

越狱插件（Theos tweak），在 Dopamine / ElleKit（rootless，`/var/jb`）环境下，按 RSSI 在不同 SSID 之间自动切换到信号更强的已知 WiFi。

- 包名：`com.liush.wifistrongest`
- 注入进程：SpringBoard（`com.apple.springboard`）
- 最低系统：iOS 15.0，架构 arm64 / arm64e
- 显示名：WiFi 择优切换

## 与 StrongerFi 的关系

StrongerFi（tateu，iOS 12–14，闭源，已停更于 2019）没有公开源码，roothide/rootless 移植包多为二次打包。本工程**不含任何原插件二进制**，是按同样的行为参数从零重写：RSSI 百分比化、区间阈值、强制阈值、最小切换差值、优先 5GHz。

## 目录

| 路径 | 职责 |
|---|---|
| `Hooks/LiushWiFiStrongestMain.xm` | SpringBoard 启动钩子 + 兜底启动 |
| `Sources/LiushWiFiStrongestEngine.m` | 节拍、阈值判定、候选打分、切换与冷却 |
| `Sources/LiushWiFiStrongestMobileWiFi.m` | MobileWiFi 私有框架 dlopen/dlsym 解析与封装 |
| `Sources/LiushWiFiStrongestConfig.m` | 配置快照（只读，面板是唯一写入方） |
| `Sources/LiushWiFiStrongestLog.m` | 落盘日志 `/var/mobile/Library/Logs/LiushWiFiStrongest.log` |
| `LiushWiFiStrongestPrefs/` | PreferenceLoader 面板 + 诊断按钮 |
| `.github/workflows/build.yml` | macOS 上编译 rootless deb 并发布 Release |

## 判定逻辑

1. 5s 静默节拍；锁屏时（若开启）直接跳过。
2. 读当前 SSID / RSSI / 信道（MobileWiFi 失败时降级到 SpringBoard 的 `SBWiFiManager` 只读模式）。
3. 当前 RSSI 低于「强制阈值」→ 立刻扫描；否则等「扫描间隔」到点，且当前 RSSI 低于「区间阈值」才扫描。
4. 扫描结果中排除同名 SSID、白名单外 SSID、冷却中的 SSID、无效 RSSI。
5. 打分：`质量 = RSSI + 100`（-100dBm→0，-50dBm→100）；开启「优先 5GHz」时给 5GHz 候选加 `容忍差值 ÷ 2` 的分。
6. 最优候选比当前高出「最小切换差值」个百分点才切；`WiFiDeviceClientAssociateAsync` 关联，失败进入冷却。

## 编译

已构建产物：`dist/com.liush.wifistrongest_5.2.0-4_iphoneos-arm64.deb`，源仓库 https://github.com/liushQAQ/WiFiStrongest 。CI 用 `macos-15` runner（`macos-14` 在本账号不可用，会秒取消）。

GitHub Actions（推荐，模板已配好 rootless）：

```sh
git init && git add . && git commit -m "init"
# 推到 GitHub 后手动触发 Build WiFiStrongest 工作流，产物在 Release
```

本地 Theos（Linux/macOS）：

```sh
export THEOS=~/theos
./build.sh rootless
```

Windows 本机没有 Theos 工具链，不要在本机直接 `make`。

## 安装

1. 装 `com.liush.wifistrongest_*_iphoneos-arm64.deb`（Sileo / Zebra / `dpkg -i`）。
2. **必须注销（respring）**：插件注入 SpringBoard 才生效。
3. 打开 设置 → WiFi 择优切换，确认「启用插件」为开；点「立即扫描一次」看日志。

## 参数

| 键 | 默认 | 说明 |
|---|---|---|
| `enabled` | 开 | 总开关 |
| `skipWhenLocked` | 开 | 锁屏不扫描（省电，StrongerFi 同款行为） |
| `debugLog` | 关 | 输出详细日志（每次扫描/每次否决都记） |
| `scanInterval` | 20 | 扫描间隔秒，最小 5 |
| `forceThreshold` | -80 | 低于此 dBm 立刻扫描 |
| `intervalThreshold` | -65 | 间隔到点时，高于此 dBm 就不扫 |
| `minDelta` | 8 | 最小切换差值（信号百分比，0=只要更强就切） |
| `prefer5G` / `prefer5GMaxDiff` | 开 / 15 | 5GHz 偏好与容忍差值 |
| `whitelist` | 空 | 逗号分隔 SSID 白名单，空=全部 |
| `autoJoinWhenDisconnected` | 关 | 未连接时是否自动连最强 |
| `failCooldown` | 300 | 切换失败后该 SSID 冷却秒数（最小 30） |
| `showWeakNetworks` | 开 | 「WiFi 详情」是否列出 -85dBm 以下网络（= 取消 iOS 的 RSSI 限制） |

## GoodWiFi 功能对照

GoodWiFi（julioverne，闭源分发但开源在 GitHub）做的是"系统 WiFi 页信息增强"，本工程把它并入同一个插件，但**不 hook 系统的「无线局域网」页面**，而是在设置里提供「WiFi 详情」页：

| GoodWiFi 功能 | 本工程 | 实现方式 |
|---|---|---|
| 取消 RSSI 限制 | ✅ | 快照里存原始 dBm 不做限幅；`showWeakNetworks` 开=全列，关=只列 ≥ -85dBm |
| 显示 MAC（BSSID） | ✅ | `WiFiNetworkGetBSSID`，缺符号时回退 `WiFiNetworkGetProperty("BSSID")` |
| 显示信道 / 频段 | ✅ | `WiFiNetworkGetChannel`，异常返回值时回退 `GetProperty("CHANNEL")`，按信道号推 2.4G/5G |
| 显示加密方式 | ✅ | `WiFiNetworkIsWPA3/SAE/WPA2/WPA/EAP` 组合成标签 |
| 显示信号强度 | ✅ | dBm + 百分比 + 颜色分级 |
| 已知网络 / 查看已保存密码 | ❌ | 需要 keychain + `com.apple.private.keychain` 级权限，注入 SpringBoard 拿不到，做不到就不假装能做 |
| 在系统 WiFi 页里内嵌显示 | ❌（有意不做） | 那是 hook Preferences 的私有 UI（`WiFiKit`/`WLAN*` 控制器），类名每个 iOS 版本都在变，没有真机可调试时等于盲写，崩溃代价远大于收益 |

数据链路：SpringBoard 侧扫描 → 写 `/var/mobile/Library/Caches/com.liush.wifistrongest/snapshot.json` → 设置面板只读该文件。面板进程（Preferences）本身没有 wlan entitlement，不能自己扫描，这也是为什么详情页要"点右上角刷新"来通知 SpringBoard 扫一次。

## 已知限制（真机必读）

1. **扫描能力取决于 entitlement**：`WiFiManagerClientCreate` 在缺 `com.apple.wlan.authentication` 时返回 NULL。本工程会在日志首行写明「私有 API 解析：可用/不可用 + 缺失符号」，不可用时自动降级为只读判断（不做切换）。若你的设备落在这一档，下一步是把扫描挪到带 entitlement 的进程，或改用 SpringBoard 自身的扫描方法——这是唯一需要真机迭代的点。
2. **验证范围**：已通过 GitHub Actions（macos-15 + Theos）真实编译并产出 deb，真机已确认设置列表出现入口、图标尺寸正常。扫描是否真能用仍以日志首行「私有 API 解析：可用/不可用」为准。
3. **二级页必须继承 `PSViewController`**（v5.2.1 修复）：Preferences 打开详情页时会向目标控制器发送 `setSpecifier:` / `setRootController:` / `setParentController:` / `initForContentSize:`，纯 `UITableViewController` 没有这些方法，点进去会 unrecognized selector 直接闪退。表格改由本类在 `loadView` 里自建。
4. **日志自描述**（v5.2.1）：引擎每次启动写一段「==== 自检 ====」，包含总开关、扫描能力、当前网络、全部阈值与白名单数量；每个「为什么没动作」只写一次（去重）；每 5 分钟一行心跳；手动扫描若撞上判定中会排队而不是丢弃。
5. 只处理**跨 SSID** 切换；同一 SSID 多 AP 的漫游由系统与路由器（802.11k/v/r）负责，插件管不到。
6. 越狱环境整体稳定性由 Dopamine 决定，插件只在 SpringBoard 内跑，不驻留守护进程、不写系统分区。
