# MacVerify 开发规划 / Development Plan

> 每个任务都有唯一编号与标题。需要开发某一项时，直接说 **「执行 D-06」**（或「执行 标题」）即可，
> 不必重复描述需求。任务完成后会把状态写回本文件，并更新下面的完成度表。

所有任务遵守同一条硬约束：

> **只呈现本机可以实测验证的信息。取不到就显示「不可用」，绝不推断、绝不兜底估算。**

这条约束决定了功能取舍：凡是需要外部数据库（保修状态、Apple 服务端配置、市场价）或需要特权
（SMC、`powermetrics`、内核扩展）的检查项，一律不做，或做成「明确标注不可用」的占位。

---

## 完成度总览

上次更新：2026-11-08 · v1.0.9

| 领域 | 完成度 | 已完成 / 总数 | 说明 |
| --- | --- | --- | --- |
| A 数据正确性 | 100% | 7 / 7 | 所有采集项均已与本机真值比对 |
| B 一致性核验 | 100% | 4 / 4 | 双通路互证，不依赖外部表 |
| C SMART | 80% | 4 / 5 | 内置 SSD 全字段可读；外接盘待验证 |
| D 原装性核对 | 100% | 12 / 12 | 41 个机型系列 / 57 个标识符，覆盖 Intel 2016–2020 与 Apple Silicon 全系 |
| E 报告与导出 | 100% | 3 / 3 | Markdown + JSON + 命令行自检 |
| F 外设与功能测试 | 100% | 5 / 5 | 无线 / 摄像头与音频 / USB 与雷雳 / 两次对比 / 报告指纹 |
| G 工程化 | 100% | 5 / 5 | 89 个单元测试 + GitHub Actions + 基线自检 + 本地化查漏 |
| **合计** | **约 98%** | **40 / 41** | 剩余 1 项为 C-05 外接盘 SMART 实测 |

状态图例：`完成` / `进行中` / `待执行` / `不做`（附原因）

---

## A 数据正确性（全部完成）

| 编号 | 标题 | 状态 |
| --- | --- | --- |
| A-01 | 电池健康度改用 AppleRawMaxCapacity 口径 | 完成 |
| A-02 | 存储容量改取物理盘，区分卷容量 | 完成 |
| A-03 | 激活锁改用 system_profiler -json 稳定 token | 完成 |
| A-04 | 崩溃日志支持 .ips / Retired，区分「读不到」与「没有」 | 完成 |
| A-05 | Shell.run 修复 stderr 死锁、输出截断、Process 释放崩溃 | 完成 |
| A-06 | 面板身份改从 SPDisplaysDataType 读取（Apple Silicon 可用） | 完成 |
| A-07 | 机型表清除事实错误，未收录机型不猜测 | 完成 |

## B 一致性核验（全部完成）

| 编号 | 标题 | 状态 |
| --- | --- | --- |
| B-01 | 机型标识 / 序列号 / 芯片 双源核对 | 完成 |
| B-02 | 磁盘容量 diskutil × IOMedia 核对 | 完成 |
| B-03 | 内建屏面板 ID × CoreGraphics 核对 | 完成 |
| B-04 | 硬盘是否 Apple 原厂介质 | 完成 |

## C SMART（4 / 5）

| 编号 | 标题 | 状态 | 数据源 |
| --- | --- | --- | --- |
| C-01 | diskutil -plist 读取 NVMe SMART 全字段 | 完成 | `SMARTDeviceSpecificKeysMayVaryNotGuaranteed` |
| C-02 | IOKit IONVMeSMARTInterface 兜底（Intel） | 完成 | IORegistry |
| C-03 | 界面与报告展示（寿命 / 备用块 / 上电时长 / 异常断电 / 介质错误 / 温度） | 完成 | — |
| C-04 | 温度开尔文→摄氏度转换 | 完成 | 实测 306 → 32.9 ℃ |
| C-05 | 外接盘 / USB 桥接盘的 SMART 支持 | 待执行 | 多数 USB 桥不转发 SMART，需按桥接芯片实测 |

**已验证字段**（Mac14,9，APPLE SSD AP1024Z，需 macOS 12+）：
`SMARTStatus`、`PERCENTAGE_USED`、`AVAILABLE_SPARE`、`AVAILABLE_SPARE_THRESHOLD`、
`DATA_UNITS_READ/WRITTEN`、`POWER_ON_HOURS`、`POWER_CYCLES`、`UNSAFE_SHUTDOWNS`、
`MEDIA_ERRORS`、`NUM_ERROR_INFO_LOG_ENTRIES`、`HOST_READ/WRITE_COMMANDS`、`TEMPERATURE`。

换算口径：`Data Units × 512,000 字节`（NVMe 规范）；温度原值为开尔文，减 273.15。

## D 原装性核对（12 / 12）

规则：只收录**已逐条对照 Apple 技术规格页**的机型；未收录机型显示「无对照数据」，不做任何判断。

同一标识符可能对应多个年代（Apple 官方机型识别文档确认）：
`MacBookAir7,2` = 13″ 2017 + Early 2015；`MacBookPro15,2` = 13″ 2018 四口 + 2019 四口。
这类条目取两代规格的并集（更宽松，不会误报），并在名称中标注年份。

| 编号 | 标题 | 状态 | 覆盖标识符 |
| --- | --- | --- | --- |
| D-01 | 15-inch 2018/2019 基线 | 完成 | MacBookPro15,1 / 15,3 |
| D-02 | 16-inch 2019 基线 | 完成 | MacBookPro16,1 / 16,4 |
| D-03 | 14/16-inch 2021 基线 | 完成 | MacBookPro18,1–18,4 |
| D-04 | M1 Air / M2 Air 基线 | 完成 | MacBookAir10,1 / Mac14,2 |
| D-05 | 14/16-inch 2023 基线 | 完成 | Mac14,5 / 14,9 / 14,6 / 14,10 |
| D-06 | Intel MacBook Air 2017–2020 | 完成 | MacBookAir7,2 / 8,1 / 8,2 / 9,1 |
| D-07 | Intel MacBook Pro 13″ 2016–2017 | 完成 | MacBookPro13,1 / 13,2 / 14,1 / 14,2 |
| D-08 | Intel MacBook Pro 15″ 2016–2017 | 完成 | MacBookPro13,3 / 14,3 |
| D-09 | Intel MacBook Pro 13″ 2018–2020 | 完成 | MacBookPro15,2 / 15,4 / 16,2 / 16,3 |
| D-10 | Apple Silicon 13″ MBP（M1 / M2） | 完成 | MacBookPro17,1 / Mac14,7 |
| D-11 | Apple Silicon Air 15″ 与 M3 / M4 全系 | 完成 | Mac14,15 / 15,12 / 15,13 / 16,12 / 16,13 |
| D-12 | Apple Silicon MBP Nov 2023 / 2024 / M5 / 2026 | 完成 | Mac15,3–15,11 / Mac16,1–16,8 / Mac17,2–17,9 / Mac17,10–17,13 / Mac18,1 |

**当前覆盖**：41 个机型系列 / 57 个标识符。机型表共收录 74 个标识符，未建基线的 17 个
都是 2012–2015 的老机型（MacBookPro9,1–12,1、MacBookAir5,1–7,1），它们仍会显示「无对照数据」。

**2026 的两块屏不能混用**：同为 14 吋，普通 Liquid Retina XDR 是 3024×1964，
PROLED XDR 是 3024×1986（16 吋为 3456×2234 对 3472×2266），因此分成两条基线。
写错分辨率会让真机被判成「换过屏」，这是必须分开的原因。

**D 系列执行要求**（缺一不可）：
1. 打开对应机型的 Apple 技术规格页，`source` 填该页链接；
2. 照抄：屏幕对角线、原生分辨率、电池标注容量与脚注实际额定容量、内存档位、存储档位、GPU 核心数；
3. Intel 机型 `gpuCores` 留空（核心数由芯片决定，不由机型决定）；
4. 存储判断按可核实程度分三态：`true` 板载焊接（容量必须落在官方档位）、`false` 可自行更换（不判断）、
   `nil` 同年份不同配置形态不一且 Apple 未公布（不判断）。**不确定就填 nil，不要猜**；
5. 在真机上跑一次报告，确认新增机型不再显示「无对照数据」且不误报。

**电池容量核对的前置条件**：Apple 公布 Wh、电池只报 mAh，换算需要电池组额定电压。
只有机器自己报告了 `DesignVoltage`（多为 Intel 机型）时才做此项；取不到就显示「不可用」。
**禁止用固定常数折算**——MacBook Air 为 2 芯约 7.6V、MacBook Pro 为 3 芯约 11.4V，用同一个常数会让整类机型误判。

## E 报告与导出（全部完成）

| 编号 | 标题 | 状态 |
| --- | --- | --- |
| E-01 | Markdown + JSON 报告，缺失项输出 null | 完成 |
| E-02 | `MACVERIFY_DUMP_REPORT` 命令行自检 | 完成 |
| E-03 | 报告含一致性核验与原装性核对章节 | 完成 |

## F 外设与功能测试（全部完成）

| 编号 | 标题 | 状态 | 数据源 |
| --- | --- | --- | --- |
| F-01 | Wi-Fi / 蓝牙硬件存在性 | 完成 | `networksetup -listallhardwareports` + IORegistry `AppleBCMWLANCore.ChipSet` / `SPBluetoothDataType` |
| F-02 | 摄像头 / 麦克风 / 扬声器存在性 | 完成 | SPCameraDataType / SPAudioDataType |
| F-03 | USB / Thunderbolt 设备树 | 完成 | SPUSBDataType / SPThunderboltDataType |
| F-04 | 两次检测对比（同机不同时间 / 两机并排） | 完成 | 报告 JSON + UserDefaults 快照（最多 12 份） |
| F-05 | 报告指纹（序列号哈希，防换头） | 完成 | CryptoKit SHA-256，取前 16 位 |

**F 系列实现备注**（写下来，避免下次又走一遍弯路）：

- **Wi-Fi 不用 `SPAirPortDataType`**：实测一次要 3.7 秒，而且会枚举周边热点。
  验机只需要「有没有这块硬件 + 芯片型号」，改用 `networksetup -listallhardwareports`（0.02s）
  加 IORegistry 的 `ChipSet`（实测 4388 → BCM4388，与蓝牙 `BCM_4388` 互相印证）。
- **`AppleBCMWLANCore` 按类名匹配不到**（DriverKit 服务，`IOServiceMatching` 返回 0），
  只能遍历 `IOUserService` 后用固件串 `wl0:` 认出无线那颗；Intel 机型仍走 `IO80211Controller` 老通路。
- **蓝牙 / 摄像头 / 音频 / USB / 雷电合并成一次 `system_profiler` 调用**：分 5 次各起一个进程要 1.2s+，
  合并后约 0.3s。整机扫描因此维持在 1.6–2.6s。
- **USB 解析用固定样例验证**：开发机没有任何 USB 设备（`SPUSBDataType` 返回空数组），
  真实设备字段只能靠合成 JSON 覆盖：总线排除、集线器递归、厂商/速率/序列号、空数组=没插设备。
  空数组与「读不到」必须区分，否则会把正常机器报成异常。
- **指纹只锁身份字段**：机型、序列号、芯片、内存、物理容量、面板、电池序列号。
  改电池循环不会让指纹变化（那是会漂移的使用痕迹），改序列号 / 换屏 / 换盘才会。

## G 工程化（5 / 5）

| 编号 | 标题 | 状态 | 落地 |
| --- | --- | --- | --- |
| G-01 | Release 通用二进制 + DMG 打包流程 | 完成 | 本地脚本流程 + CI `package` job |
| G-02 | 单元测试 | 完成 | `Tests/MacVerifyTests/`，8 个文件 89 个用例 |
| G-03 | GitHub Actions：构建 + 测试 + 产物 | 完成 | `.github/workflows/ci.yml`，verify / build / package 三段 |
| G-04 | 机型基线覆盖率自检脚本 | 完成 | `Scripts/check_baseline.py` |
| G-05 | 本地化字符串查漏 | 完成 | `Scripts/check_localization.py` |

**跑测试与自检**

```bash
swift test --parallel                              # 89 个用例
python3 Scripts/check_baseline.py                  # 基线完整性与覆盖率
python3 Scripts/check_localization.py              # 漏翻中文
python3 Scripts/check_baseline.py --strict         # 把「未建基线」也当失败
```

> 在受限环境（禁用了 sandbox-exec）里跑 SwiftPM 需要加 `--disable-sandbox`，
> 否则编译 Package.swift 时报 `sandbox_apply: Operation not permitted`。
> 同理，Xcode 命令行构建在干净 DerivedData 下需要 `OTHER_SWIFT_FLAGS="-disable-sandbox"`
> 才能加载 SwiftUI 的宏插件。这两者都是环境限制，不是工程问题；CI 上不需要。

**G 系列实现备注**（避免下次重走弯路）

- **测试用 SPM 而不是 Xcode test target**：`Package.swift` 把 `MacVerify/` 编译成
  `MacVerifyCore`（排除 `App/`，因为那里有 `@main`），`swift test` 在命令行与 CI 上直接可跑。
  Xcode 工程仍是 App 的唯一构建方式，两者共读同一份源码，不会漂移。
- **用例不依赖本机硬件**：全部用合成数据，CI 上没有电池、没有内建屏也跑得通。
  只有报告的端到端用例读真实接口，且只断言结构、不断言具体数值。
- **每个用例独立 UserDefaults 域**：`ScanHistoryStore` 改成可注入 `UserDefaults`。
  并行执行时共用一个域会出现「单跑通过、`--parallel` 失败」的假象，第一次跑就踩到了。
- **自检脚本要能抓错才算数**：`check_baseline.py` 用篡改副本验证过 6 类错误
  （重复标识符、来源非 Apple 页、实际容量大于标注、档位窗口重叠、外形图缺失、分辨率与尺寸不匹配），
  全部返回非零。`check_localization.py` 同样用样例验证过 4 类漏翻，并确认已包裹 / 嵌套 / 注释三类不误报。
- **脚本自己也要防「假绿」**：解析到的条目数必须等于源码里的字面量数量，否则说明格式变了、正则漏抓，
  直接报错而不是静默跳过。
- **CI 的 tag 打包会校验版本一致**：`MARKETING_VERSION` 与 tag 不一致时直接失败，
  避免出现「发了 v1.0.9，包里还是 1.0.8」这种只能靠人眼发现的问题。

## 明确不做

| 需求 | 原因 |
| --- | --- |
| 电池温度 / 风扇转速 / CPU 温度 | Apple Silicon 无用户态接口，需特权或私有 API |
| 激活锁解除状态、保修剩余、是否官翻 | 需要 Apple 服务端，涉及账号与联网 |
| 屏幕坏点自动判定 | 需摄像头拍摄屏幕，受环境光与摩尔纹影响，无法保证准确 |
| 二手估价 | 依赖市场数据，不是本机硬件事实 |

---

## 附：口径与约束（所有任务通用）

1. **双源可验证**：新增结论必须能给出至少一条独立通路复核；
2. **缺失即不可用**：取不到数据时显示「不可用」，禁止用 0 / false / 估算值填充；
3. **文案不加码**：不确定的结论用「建议确认」，不用「非原装」「故障」；
4. **不引入未核验的外部表**：新表必须写明官方来源，未覆盖项显示「无对照数据」；
5. **实机验证**：至少在一台 Apple Silicon 上跑通；Release 版需再用 DMG 内应用复验一次。
