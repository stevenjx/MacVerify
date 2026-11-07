# MacVerify

**Hardware inspection for used MacBooks.** Every value comes from this Mac's own read-only interfaces.
When a sensor or identifier is not exposed, MacVerify says so — it never guesses, interpolates, or fills in a default.

**二手 MacBook 硬件质检工具。** 所有数值均来自本机只读接口。当某项数据本机不对外暴露时，
界面如实显示「不可用」，不做估算、不做补值、不用 0 或 false 冒充。

macOS 12 Monterey+ · Universal binary (Intel & Apple Silicon) · 中英双语 · 不联网

![Overview](docs/screenshots/01-overview-zh.png)

---

## 为什么可信 / Why it can be trusted

二手验机最容易出问题的地方不是"读不到"，而是"读错了还看不出来"。MacVerify 对每一类结论都给出可复核的依据。

Used-Mac checks usually fail not by returning nothing, but by returning something plausible and wrong.
MacVerify makes the evidence behind every claim inspectable.

| 做法 | 说明 |
| --- | --- |
| **缺失即不可用** | 取不到数据时输出 `null` / 「不可用」。例如崩溃日志目录无权限时显示「无法读取」，而不是「无崩溃记录」 |
| **双通路互证** | 机型、序列号、芯片、磁盘容量、内建屏、内存各自从两条独立通路读取并比对，不一致即报告。用于识别改机型、刷序列号、换屏、换盘 |
| **统一口径** | 电池健康度采用 `AppleRawMaxCapacity ÷ DesignCapacity`，与「系统设置 → 电池」显示的数字一致 |
| **不写死易错数据** | 机型表只收录 Apple 官方标识符，不把芯片写进机型名（同一标识符常对应多个芯片），未收录机型显示「未收录」而非猜测 |
| **可导出复核** | 质检报告导出为 Markdown + JSON，每次检测都可留证、可比对 |

## 功能 / Features

| 模块 | 检查内容 |
| --- | --- |
| 概览 | 机型、芯片、内存、容量、电池健康、激活锁、FileVault、MDM、崩溃记录一站式汇总 |
| 一致性核验 | 机型 / 序列号 / 芯片 / 磁盘容量 / 内建屏 / 内存各自双通路比对 |
| 原装性核对 | 内建屏分辨率与对角线、内存与存储档位、GPU 核心数、电池容量，对照 Apple 官方技术规格（仅限已收录机型，未收录显示「无对照数据」）|
| 设备信息 | 机型标识、营销名称、机壳型号、配置编号、序列号、核心构成、GPU 核心数、系统版本 |
| 安全与合规 | 激活锁、FileVault、SIP、Gatekeeper、MDM 注册、远程管理描述文件、内核崩溃统计（含 `.ips`）|
| 显示屏 | 原生分辨率、刷新率、缩放倍率、面板厂商/型号/序列号/类型（Apple Silicon 亦可读）、纯色检查 |
| 存储 | 磁盘型号、标称与物理容量、SMART 寿命、累计读写字节、顺序读写实测（8 MB 块 + `F_FULLFSYNC` 落盘）|
| 性能测试 | CPU 单核/多核吞吐、Metal 计算管线持续负载（真实批次/秒）|
| 键盘与触控板 | 逐键触发与覆盖统计、修饰键左右区分、caps lock 触发、触控板定位与压力轨迹 |
| 电池 | 设计容量、满充容量、健康度（与系统设置同口径）、循环、电压电流、内阻估算（ΔV/ΔI）|
| 电池负载测试 | 真实放电采样，给出容量一致性、电压下降（含电量分量）、温升判定并保存历史 |
| 供电 | 适配器功率、充电状态、实时功率、剩余时间 |
| 报告 | 导出 Markdown + JSON，缺失项输出 `null` / `unavailable` |

界面支持 **跟随系统 / 简体中文 / English**，以及 **跟随系统 / 浅色 / 深色**，切换即时生效。

## 数据来源 / Data sources

所有数值均来自本机只读接口，且命令行工具一律以 `-json` / `-plist` 解析，不受系统语言影响：

- `IOKit`：`AppleSmartBattery`、`IOPlatformExpertDevice`、`IOBlockStorageDriver`、`NVMe SMART`、`IODisplayConnect`
- `sysctl` / `ProcessInfo`：芯片、核心、内存、系统版本、低电量模式
- `CoreGraphics` / `AppKit`：显示器尺寸、原生分辨率、刷新率、色彩配置
- 只读系统命令：`system_profiler`、`fdesetup`、`csrutil`、`spctl`、`profiles`、`diskutil`

## 关键口径 / Definitions

- **电池健康度**：`AppleRawMaxCapacity ÷ DesignCapacity`，与 macOS「系统设置 → 电池」一致
  （实测：设计 6075 mAh、满充 5441 mAh → 89.6%，系统显示 90%）
- **存储容量**：取物理盘 `diskutil TotalSize` 并按零售规格归一（1000.6 GB → 1TB），与「根卷可用容量」分开显示
- **负载压降**：测试期间电量同步下降，端电压下降包含 SOC 分量，不等同于内阻
- **一致性核验**：同一事实双通路比对，不依赖外部规格表；未收录机型不做推断

## 系统要求 / Requirements

- macOS 12.0 Monterey 或更高
- Intel 与 Apple Silicon 均可（Release 为 x86_64 + arm64 通用二进制）
- 无沙盒、无后台常驻、无内核扩展、无特权 helper

## 安装 / Install

1. 下载 `MacVerify-1.0.1.dmg`
2. 打开后将 `MacVerify.app` 拖入「应用程序」
3. 首次打开如提示"无法验证开发者"，右键点击应用 → 打开
   （或执行 `xattr -dr com.apple.quarantine /Applications/MacVerify.app`）

应用为本地 ad-hoc 签名，未做 Apple 公证。

## 从源码构建 / Build

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project "MacVerify.xcodeproj" -scheme MacVerify \
  -configuration Release -destination 'generic/platform=macOS' \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  -derivedDataPath build build
```

命令行入口：

- `MACVERIFY_PAGE=<overview|hardware|security|display|storage|performance|input|battery|loadTest|power|about>`
  直接打开指定页面
- `MACVERIFY_DUMP_REPORT=/tmp/report.md` 采集一次并导出 Markdown + JSON 后退出（用于自动化核验）

## 隐私 / Privacy

不联网、不上传、不写入系统设置。检测数据仅保存在本机 `UserDefaults`。

## 已知限制 / Limitations

- **SMART 与电池温度**：Apple Silicon 机型通常不向第三方公开，显示为「不可用」。
- **EDID 原始块**：Apple Silicon 不提供；面板厂商/型号/序列号改从 `SPDisplaysDataType` 读取，仍然可用。
- **面板生产批次**：多数内建屏不写入生产日期，显示「不可用」，不按 0 值算成 1990 年。
- **激活锁**：状态由系统在联网后返回；离线时可能读不到。
- **充电上限**：macOS 在系统设置中管理，第三方应用无法安全改写，本工具只读取状态。
- **压降与内阻**：必须在电池供电、真实放电时才有效；接电源时该项会被排除。
- **机型表**：只收录 Apple 官方支持文档列出的标识符；未收录机型显示「未收录的机型（MacXX,Y）」，
  不按前缀猜尺寸或年份。

## Changelog

### 1.0.1
- 新增**原装性核对**：内建屏分辨率/对角线、内存与存储档位、GPU 核心数、电池容量，
  与该机型的 Apple 官方技术规格比对；未收录机型显示「无对照数据」，不做判断
- 新增机型规格基线（`ModelSpecCatalog`），每条注明 Apple 技术规格页来源
- 新增电池数据自洽校验：满充容量显著高于设计容量时提示数据被改写
- 从外接盘启动时，存储相关核对自动跳过并说明原因
- 报告与概览新增对应章节 / 卡片

### 1.0.0
首个公开版本（重置版本号，取代此前的 1.0.0 / 1.0.1 预览发布）。

- 新增**一致性核验**：机型、序列号、芯片、磁盘容量、内建屏、内存各自双通路比对
- 新增**质检报告导出**：Markdown + JSON，缺失项输出 `null`，支持 `MACVERIFY_DUMP_REPORT` 命令行自检
- 修正电池健康度口径（改用 `AppleRawMaxCapacity`），与系统设置一致（92.0% → 89.6%，系统显示 90%）
- 修正存储容量：改用物理盘容量，1TB 机器不再显示为 995 GB
- 修正激活锁解析：改用 `system_profiler -json`，避免中文系统下静默失败
- 修正崩溃日志统计：支持 macOS 13+ 的 `.ips`（bug_type 210）与 `Retired/`；目录不可读时显示「无法读取」
- 修正 `Shell.run`：stderr 死锁、输出截断、`Process` 释放崩溃（task still running）
- 修正面板身份来源：Apple Silicon 上可从系统报告读取面板 vendor / product / serial
- 修正机型表：`MacBookPro16,4` 归为 16-inch 2019；不再给同一标识符硬写芯片型号；未收录机型不猜测
- 修正 EDID 解析：校验 128 字节校验和，year=0 视为未知
- 移除电池负载测试中编造的「每循环 0.03%」衰减模型
- 统一全 App 电池健康度分级（唯一 `HealthGrade`）

## 开发规划 / Roadmap

见 [docs/DEVELOPMENT_PLAN.md](docs/DEVELOPMENT_PLAN.md)。
