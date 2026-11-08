#!/usr/bin/env python3
"""机型基线覆盖率与完整性自检。

为什么单独写脚本：这张表一旦出错，后面所有「原装性」判断都是错的，
而且错得很安静——程序不报错，只是给出一个看起来煞有介事但事实错误的结论。

用法：
    python3 Scripts/check_baseline.py           # 在仓库根目录运行
    python3 Scripts/check_baseline.py --strict  # 把「未建基线」也算失败

退出码：0 通过（可能有提示），1 有错误。
"""
import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPEC_FILE = ROOT / "MacVerify/Models/ModelSpecCatalog.swift"
CATALOG_FILE = ROOT / "MacVerify/Models/MacModelCatalog.swift"
ASSETS = ROOT / "MacVerify/Assets.xcassets"

errors: list[str] = []
warnings: list[str] = []


def read(path: pathlib.Path) -> str:
    if not path.is_file():
        errors.append(f"找不到文件：{path.relative_to(ROOT)}")
        return ""
    return path.read_text(encoding="utf-8")


def parse_specs(text: str) -> list[dict]:
    """解析 ModelSpecCatalog 里的条目。条目格式固定，逐块正则提取。"""
    specs = []
    blocks = re.split(r"\n\s*ModelSpec\(", text)

    def numbers(block: str, key: str) -> list[int]:
        match = re.search(rf"{key}: \[([^\]]*)\]", block)
        return [int(x) for x in re.findall(r"-?\d+", match.group(1))] if match else []

    for block in blocks[1:]:
        ids = re.search(r"identifiers: \[([^\]]*)\]", block)
        name = re.search(r'name: "([^"]*)"', block)
        if not ids or not name:
            continue
        source = re.search(r'source: "([^"]*)"', block)
        inches = re.search(r"displayInches: ([\d.]+)", block)
        width = re.search(r"nativeWidth: (\d+)", block)
        height = re.search(r"nativeHeight: (\d+)", block)
        rated = re.search(r"batteryRatedWh: ([\d.]+)", block)
        actual = re.search(r"batteryActualWh: ([\d.]+)", block)
        soldered = re.search(r"storageSoldered: (\w+)", block)
        specs.append({
            "identifiers": re.findall(r'"([^"]*)"', ids.group(1)),
            "name": name.group(1),
            "source": source.group(1) if source else "",
            "memory": numbers(block, "memoryOptionsGB"),
            "storage": numbers(block, "storageOptionsGB"),
            "gpu": numbers(block, "gpuCores"),
            "inches": float(inches.group(1)) if inches else 0.0,
            "width": int(width.group(1)) if width else 0,
            "height": int(height.group(1)) if height else 0,
            "rated": float(rated.group(1)) if rated else 0.0,
            "actual": float(actual.group(1)) if actual else None,
            "soldered": soldered.group(1) if soldered else "true",
        })
    return specs


def parse_catalog(text: str) -> list[dict]:
    entries = []
    for m in re.finditer(
        r'\.init\(identifier: "([^"]+)", name: "([^"]*)", image: ("([^"]*)"|nil), modelNumber: ("([^"]*)"|nil)\)',
        text,
    ):
        entries.append({
            "identifier": m.group(1),
            "name": m.group(2),
            "image": m.group(4),
            "model_number": m.group(6),
        })
    return entries


def check_counts(spec_text: str, catalog_text: str, specs: list[dict], entries: list[dict]) -> None:
    """解析到的条数必须和源码里的字面量出现次数一致。

    否则说明格式变了、正则漏抓——那会让下面的检查「看起来全绿」。
    这是文本解析最容易犯的错，单独设一道闸。
    """
    declared = len(re.findall(r"^\s*ModelSpec\($", spec_text, re.M))
    if declared != len(specs):
        errors.append(f"ModelSpec 条目解析不完整：源码 {declared} 处，解析到 {len(specs)} 条")

    literal_entries = catalog_text.count(".init(identifier:")
    if literal_entries != len(entries):
        errors.append(f"机型表条目解析不完整：源码 {literal_entries} 处，解析到 {len(entries)} 条")


def check_specs(specs: list[dict]) -> None:
    seen: dict[str, str] = {}
    for spec in specs:
        name = spec["name"] or "(无名称)"

        if not spec["identifiers"]:
            errors.append(f"{name}：没有任何标识符")
        if not spec["name"]:
            errors.append("存在没有名称的基线条目")
        elif "MacBook" not in spec["name"]:
            errors.append(f"{name}：名称不符合 Apple 官方写法")

        if not spec["source"].startswith("https://support.apple.com/"):
            errors.append(f"{name}：来源不是 Apple 支持页（{spec['source'] or '空'}）")

        for identifier in spec["identifiers"]:
            if identifier in seen:
                errors.append(f"{identifier} 同时出现在「{seen[identifier]}」与「{name}」")
            seen[identifier] = name

        # 屏幕
        if not (10.0 <= spec["inches"] <= 18.0):
            errors.append(f"{name}：对角线 {spec['inches']}″ 不合理")
        if spec["width"] <= 0 or spec["height"] <= 0:
            errors.append(f"{name}：分辨率缺失")
        elif spec["width"] <= spec["height"]:
            errors.append(f"{name}：分辨率不是横屏（{spec['width']}×{spec['height']}）")
        else:
            diagonal = (spec["width"] ** 2 + spec["height"] ** 2) ** 0.5
            ppi = diagonal / spec["inches"] if spec["inches"] else 0
            # Retina 约 220–260，非 Retina（2015 Air 的 1440×900）约 128
            if not (100.0 <= ppi <= 300.0):
                errors.append(f"{name}：像素密度 {ppi:.0f} ppi 不合理，分辨率与尺寸不匹配")

        # 电池
        if not (0 < spec["rated"] < 120):
            errors.append(f"{name}：电池标注容量 {spec['rated']} Wh 不合理")
        actual = spec["actual"] if spec["actual"] is not None else spec["rated"]
        if actual > spec["rated"] + 0.001:
            errors.append(f"{name}：实际额定 {actual} Wh 大于标注 {spec['rated']} Wh")

        # 档位列表
        for key, label in (("memory", "内存"), ("storage", "存储"), ("gpu", "GPU 核心")):
            values = spec[key]
            if key != "gpu" and not values:
                errors.append(f"{name}：没有{label}档位")
            if values != sorted(values):
                errors.append(f"{name}：{label}档位未排序 {values}")
            if len(values) != len(set(values)):
                errors.append(f"{name}：{label}档位有重复 {values}")

        # 存储匹配窗口 [×0.93, ×1.02] 不能与相邻档位重叠
        options = sorted(spec["storage"])
        for lower, upper in zip(options, options[1:]):
            if upper * 0.93 <= lower * 1.02:
                errors.append(f"{name}：{lower}/{upper} 档位匹配窗口重叠")


def check_catalog(entries: list[dict]) -> None:
    seen = set()
    for entry in entries:
        if entry["identifier"] in seen:
            errors.append(f"机型表重复标识符：{entry['identifier']}")
        seen.add(entry["identifier"])

        if not entry["name"]:
            errors.append(f"{entry['identifier']}：没有机型名称")

        if entry["model_number"] and not re.fullmatch(r"A\d{4}", entry["model_number"]):
            errors.append(f"{entry['identifier']}：机壳型号格式不对（{entry['model_number']}）")

        if entry["image"] and not (ASSETS / f"{entry['image']}.imageset").is_dir():
            errors.append(f"{entry['identifier']}：引用的外形图不存在（{entry['image']}）")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--strict", action="store_true", help="把「未建基线」也视为失败")
    args = parser.parse_args()

    spec_text = read(SPEC_FILE)
    catalog_text = read(CATALOG_FILE)
    if errors:
        for error in errors:
            print(f"错误：{error}")
        return 1

    specs = parse_specs(spec_text)
    entries = parse_catalog(catalog_text)

    check_counts(spec_text, catalog_text, specs, entries)
    check_specs(specs)
    check_catalog(entries)

    spec_identifiers = {i for spec in specs for i in spec["identifiers"]}
    catalog_identifiers = {e["identifier"] for e in entries}

    for identifier in sorted(spec_identifiers - catalog_identifiers):
        errors.append(f"{identifier} 有规格基线，但机型表里没有名称")
    uncovered = sorted(catalog_identifiers - spec_identifiers)

    print("机型基线自检")
    print(f"  规格基线      {len(specs)} 个系列 / {len(spec_identifiers)} 个标识符")
    print(f"  机型名称表    {len(entries)} 个标识符")
    print(f"  未建基线      {len(uncovered)} 个（界面显示「无对照数据」，不做判断）")
    for identifier in uncovered:
        print(f"                · {identifier}")
    print()

    for warning in warnings:
        print(f"提示：{warning}")

    if errors:
        for error in errors:
            print(f"错误：{error}")
        print(f"\n失败：{len(errors)} 项错误")
        return 1

    if args.strict and uncovered:
        print(f"失败（--strict）：{len(uncovered)} 个机型未建基线")
        return 1

    print("通过：没有发现基线数据错误")
    return 0


if __name__ == "__main__":
    sys.exit(main())
