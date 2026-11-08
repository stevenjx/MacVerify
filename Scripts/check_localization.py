#!/usr/bin/env python3
"""本地化查漏：找出漏掉 T() 包裹的中文文案。

为什么需要：这个 App 的中文与英文是同一个调用的两个参数（T("中文", "English")）。
漏掉 T() 的字符串在英文界面下会直接显示中文，而代码本身不会报错——
编译通过、测试通过，只有切到英文的用户会看到。

检查项：
  1. 含中文的字符串字面量不在任何 T(...) 调用内          → 漏翻
  2. T() 只有一个参数                                   → 缺英文
  3. T() 的第二个参数里含中文                            → 英文侧粘了中文
  4. T() 的参数为空                                      → 空文案

扫描规则（不能只靠正则，因为 Swift 字符串可以插值）：
  - 注释整段跳过，字符串内的 `//` 不当注释；
  - `"…\\(expr)…"` 中插值表达式的引号不会提前结束外层字符串；
  - 三引号字符串整段取出；
  - 进入 T( 时记录括号深度，深度回落前出现的字符串都算「已包裹」。

用法：python3 Scripts/check_localization.py [目录或文件]
退出码：0 通过，1 有问题。
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_SCOPE = ROOT / "MacVerify"

# 只认汉字本身。全角标点（：、（））常作分隔符，两种语言下都成立，不算漏翻。
CJK = re.compile(r"[\u4e00-\u9fff]")

# 文件级豁免：这些文件里的中文是数据或专名，不是可切换的界面文案。
EXEMPT = {
    "Services/ReportService.swift": "报告导出的标签固定为中文（字段键是英文），不随界面语言变化",
    "Core/Localization.swift": "语言名用本语言显示（如「简体中文」），这是通行做法",
}


def find_close(text: str, open_index: int):
    """text[open_index] 是 '('，返回与之配对的 ')' 下标；找不到返回 None。

    需要处理字符串与插值：`T("a \\(f(x)) b", "c")` 中 `f(x)` 的括号要计入深度。
    """
    depth = 1
    state = "code"
    return_to_string = []  # 每层插值进入 code 前的深度
    i = open_index + 1
    while i < len(text):
        c = text[i]
        if state == "code":
            if c == '"':
                if text.startswith('"""', i):
                    state = "multiline"
                    i += 3
                    continue
                state = "string"
            elif c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
                if return_to_string and depth == return_to_string[-1]:
                    return_to_string.pop()
                    state = "string"
                elif depth == 0:
                    return i
            elif text.startswith("//", i):
                j = text.find("\n", i)
                i = len(text) if j < 0 else j
                continue
            elif text.startswith("/*", i):
                j = text.find("*/", i + 2)
                i = len(text) if j < 0 else j + 2
                continue
        elif state == "string":
            if c == "\\":
                if text.startswith("\\(", i):
                    return_to_string.append(depth)
                    depth += 1          # 插值自己的 '(' 也算一层
                    state = "code"
                    i += 2
                    continue
                i += 2
                continue
            if c == '"':
                state = "code"
        elif state == "multiline":
            if text.startswith('"""', i):
                state = "code"
                i += 3
                continue
        i += 1
    return None


def scan_leaks(text: str):
    """返回 [(行号, 片段)]：不在 T(...) 内的含中文字符串。"""
    leaks = []
    i = 0
    n = len(text)
    line = 1
    depth = 0
    t_depths = []

    while i < n:
        c = text[i]

        if c == "\n":
            line += 1
            i += 1
            continue

        if text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue

        if text.startswith("/*", i):
            j = text.find("*/", i + 2)
            end = n if j < 0 else j + 2
            line += text.count("\n", i, end)
            i = end
            continue

        if c == "T" and text.startswith("T(", i) and (i == 0 or not (text[i - 1].isalnum() or text[i - 1] == "_")):
            depth += 1
            t_depths.append(depth)
            i += 2
            continue

        if c == '"':
            if text.startswith('"""', i):
                j = text.find('"""', i + 3)
                end = n if j < 0 else j
                content = text[i + 3:end]
                if CJK.search(content) and not t_depths:
                    first_line = content.strip().splitlines()[0] if content.strip() else ""
                    leaks.append((line, first_line[:60]))
                line += content.count("\n")
                i = end + 3
                continue

            j = i + 1
            content = []
            while j < n:
                ch = text[j]
                if ch == "\\":
                    if text.startswith("\\(", j):
                        close = find_close(text, j + 1)
                        stop = n if close is None else close + 1
                        # 插值里可能还有自己的 T("中文","English")，那是独立的一次调用，
                        # 由 check_pairs 单独检查；这里只留占位符，避免把它的中文算到外层。
                        content.append("X")
                        line += text.count("\n", j, stop)
                        j = stop
                        continue
                    content.append(text[j:j + 2])
                    j += 2
                    continue
                if ch == '"':
                    break
                content.append(ch)
                j += 1
            literal = "".join(content)
            if CJK.search(literal) and not t_depths:
                leaks.append((line, literal.strip()[:60]))
            i = j + 1
            continue

        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if t_depths and depth < t_depths[-1]:
                t_depths.pop()
        i += 1

    return leaks


def strip_interpolation(args: str) -> str:
    out = []
    i = 0
    while i < len(args):
        if args.startswith("\\(", i):
            close = find_close(args, i + 1)
            i = len(args) if close is None else close + 1
            out.append("X")
            continue
        out.append(args[i])
        i += 1
    return "".join(out)


def split_first_two(args: str):
    """按第一个顶层逗号切成两段。"""
    depth = 0
    in_string = False
    i = 0
    while i < len(args):
        c = args[i]
        if in_string:
            if c == "\\":
                if args.startswith("\\(", i):
                    close = find_close(args, i + 1)
                    i = len(args) if close is None else close + 1
                    continue
                i += 2
                continue
            if c == '"':
                in_string = False
        else:
            if c == '"':
                in_string = True
            elif c in "([":
                depth += 1
            elif c in ")]":
                depth -= 1
            elif c == "," and depth == 0:
                return args[:i], args[i + 1:]
        i += 1
    return args, None


def literal_body(argument: str) -> str:
    """取参数去掉首尾引号后的内容；不是字符串字面量时返回空串。"""
    text = argument.strip()
    if len(text) < 2 or not text.startswith('"') or not text.endswith('"'):
        return ""
    return text[1:-1]


def check_pairs(text: str):
    """T(...) 的参数完整性。返回 [(行号, 问题, 片段)]。"""
    problems = []
    for match in re.finditer(r"\bT\(", text):
        # 函数声明 `func T(_ chinese: String, _ english: String)` 不是调用
        if re.search(r"\bfunc\s+$", text[:match.start()]):
            continue
        open_index = match.end() - 1
        close = find_close(text, open_index)
        line = text[:match.start()].count("\n") + 1
        if close is None:
            problems.append((line, "T() 括号未闭合", ""))
            continue

        args = text[open_index + 1:close]
        if "," not in strip_interpolation(args):
            problems.append((line, "T() 只有一个参数（缺少英文）", args.strip()[:60]))
            continue

        first, second = split_first_two(args)
        if first is None or second is None:
            continue
        if not literal_body(first):
            problems.append((line, "T() 第一个参数为空", second.strip()[:60]))
        if not literal_body(second):
            problems.append((line, "T() 第二个参数为空", first.strip()[:60]))
        elif CJK.search(literal_body(second)):
            problems.append((line, "T() 的英文参数里含中文", second.strip()[:60]))
    return problems


def main() -> int:
    scope = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SCOPE
    if not scope.exists():
        print(f"找不到路径：{scope}")
        return 1

    files = [scope] if scope.is_file() else sorted(scope.rglob("*.swift"))
    findings = []

    for path in files:
        text = path.read_text(encoding="utf-8")
        resolved = path.resolve()
        key = "/".join(resolved.parts[-2:])
        exempt = key in EXEMPT

        if not exempt:
            for line, snippet in scan_leaks(text):
                findings.append((path, line, "含中文的字符串没有 T() 包裹", snippet))

        for line, kind, snippet in check_pairs(text):
            findings.append((path, line, kind, snippet))

    if not findings:
        print(f"本地化查漏：{len(files)} 个文件，未发现漏翻")
        return 0

    def shown(path: pathlib.Path) -> str:
        try:
            return str(path.resolve().relative_to(ROOT))
        except ValueError:
            return str(path)

    findings.sort(key=lambda item: (str(item[0]), item[1]))
    for path, line, kind, snippet in findings:
        print(f"{shown(path)}:{line}: {kind} → {snippet}")
    print(f"\n发现 {len(findings)} 处问题")
    return 1


if __name__ == "__main__":
    sys.exit(main())
