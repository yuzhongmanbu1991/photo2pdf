#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
工程自检脚本（Windows 上没有 Swift 编译器时的替代方案）。

检查内容：
  1. 所有 .swift 文件用 tree-sitter-swift 做语法解析，必须没有 ERROR / MISSING 节点；
  2. project.yml 用 PyYAML 载入，并校验关键字段（target / bundle id / iOS 16 / scheme）；
  3. .github/workflows/*.yml 用 PyYAML 载入，并校验关键步骤（macos-15 / 关闭签名 / 打包 Payload）；
  4. 所有 Assets 下的 Contents.json 是合法 JSON，且引用的图片存在；
  5. AppIcon 是 1024x1024、无 alpha 通道的 PNG（用 Pillow，可选）；
  6. 代码风格风险扫描：强制解包 try! / as!、iOS 17+ 专属 API 的裸用、TODO 等。

用法：
  .venv\\Scripts\\python.exe scripts\\self_check.py            # 运行并把报告写到 docs/SELF-CHECK.md
  .venv\\Scripts\\python.exe scripts\\self_check.py --no-write # 只打印，不写文件
"""

from __future__ import annotations

import json
import os
import platform
import re
import sys
from datetime import datetime

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES_DIR = os.path.join(BASE_DIR, "Sources")
RESOURCES_DIR = os.path.join(BASE_DIR, "Resources")
DOCS_DIR = os.path.join(BASE_DIR, "docs")
REPORT_PATH = os.path.join(DOCS_DIR, "SELF-CHECK.md")

# 本项目最低 iOS 15.0：下面这些是 iOS 16 / 17 才有的 SwiftUI API，
# 一旦出现就会在 iOS 15 的部署目标下报「only available in iOS 16.0 or newer」，
# 或者在 iOS 15 真机上直接不显示/崩溃。全部禁止使用（注释里提到不算）。
IOS16_PLUS_APIS = [
    # ---- 导航 / 列表（iOS 16） ----
    "NavigationStack",
    "NavigationSplitView",
    ".navigationDestination(",
    ".navigationStack(",
    # ---- 选择照片（iOS 16） ----
    "PhotosPicker",
    "PhotosPickerItem",
    # ---- 分享 / 弹层（iOS 16） ----
    "ShareLink",
    ".presentationDetents(",
    ".presentationBackground(",
    ".presentationCornerRadius(",
    ".presentationDragIndicator(",
    # ---- 容器 / 布局（iOS 16） ----
    "Grid {",
    "Grid(",
    ".gridCellColumns(",
    ".gridCellAnchor(",
    "ViewThatFits",
    "AnyLayout",
    "ContentUnavailableView",
    "@Observable",
    "LabeledContent",
    # ---- 滚动 / 外观（iOS 16） ----
    ".scrollContentBackground(",
    ".scrollIndicators(",
    ".scrollDismissesKeyboard(",
    ".scrollBounceBehavior(",
    ".contentMargins(",
    ".scrollTargetBehavior(",
    ".scrollPosition(",
    ".defaultScrollAnchor(",
    ".containerRelativeFrame(",
    ".toolbarBackground(",
    ".toolbarColorScheme(",
    ".toolbarRole(",
    ".topBarLeading",
    ".topBarTrailing",
    # ---- 交互 / 动画（iOS 16/17） ----
    ".symbolEffect(",
    ".phaseAnimator(",
    ".keyframeAnimator(",
    ".sensoryFeedback(",
    ".onGeometryChange(",
    ".visualEffect(",
    ".inspector(",
    # ---- 文本（View 级别，iOS 16） ----
    ".fontDesign(",
    ".bold()",
    ".italic()",
    ".monospaced()",
]
# 双参数 onChange 是 iOS 17+；单参数版 iOS 14 起就有（本项目用的就是单参数版）
TWO_PARAM_ONCHANGE = re.compile(
    r"\.onChange\(of:\s*[^)]*\)\s*\{\s*[A-Za-z_][A-Za-z0-9_]*\s*,\s*[A-Za-z_][A-Za-z0-9_]*\s+in"
)
# 只有在 iOS 16+ 才加入的 SF Symbol：iOS 15 上不会崩，但图标会空一块
IOS16_ONLY_SYMBOLS = ["photo.badge.plus", "doc.badge.arrow.up"]

# 已完成的 iOS 15 替代清单（写进报告，方便以后 review 或回退）
IOS15_SUBSTITUTIONS = [
    ("NavigationStack", "NavigationView + StackNavigationViewStyle()（iOS 13）", "iOS 13"),
    ("PhotosPicker / PhotosPickerItem", "MultiPhotoPicker（PHPickerViewController 桥接）", "iOS 14"),
    ("PHPickerConfiguration.preferredAssetRepresentationMode", "= .current，HEIC 保持原格式", "iOS 14"),
    ("NSItemProvider.loadTransferable（异步取 Data）", "loadFileRepresentation 优先 / loadDataRepresentation 兜底", "iOS 11"),
    (".presentationDetents([.medium, .large])", "删除，sheet 用系统默认高度", "-"),
    ("ShareLink", "ShareSheet（UIActivityViewController）", "iOS 13"),
    ("Grid / GridItem（Grid 容器）", "LazyVGrid + GridItem（本项目一直用的就是它）", "iOS 14"),
    ("SF Symbol photo.badge.plus", "photo.on.rectangle", "iOS 14"),
    ("SF Symbol doc.badge.arrow.up", "doc.text", "iOS 13"),
    ("iOS 17 双参数 onChange", "iOS 14 单参数 onChange(of:) { newValue in }", "iOS 14"),
]

# v2.0 新增能力：扫描（VisionKit）/ 滤镜（Core Image）/ OCR（Vision）
# 每项 = (检查项名称, 文件, 必须出现的关键写法)
SCAN_MARKERS = [
    ("相机扫描（VisionKit 桥接）", "Sources/Views/DocumentScannerView.swift",
     ["import VisionKit", "VNDocumentCameraViewController", "VNDocumentCameraViewControllerDelegate",
      "isSupported", "documentCameraViewController"]),
    ("相机权限（AVFoundation）", "Sources/Views/DocumentScannerView.swift",
     ["AVCaptureDevice.authorizationStatus", "requestAccess"]),
    ("OCR 识别（Vision）", "Sources/Services/TextRecognizer.swift",
     ["import Vision", "VNRecognizeTextRequest", ".accurate", "zh-Hans", "recognitionLanguages"]),
    ("OCR 流程（进度/取消）", "Sources/Services/OCRController.swift",
     ["OCRRunner", "actor", "Task.checkCancellation", "is CancellationError"]),
    ("增强滤镜（Core Image）", "Sources/Services/ImageEnhancer.swift",
     ["import CoreImage", "CIColorControls", "CIUnsharpMask", "CIHighlightShadowAdjust", "CIContext"]),
    ("扫描入口与全屏呈现", "Sources/Views/ContentView.swift",
     ["DocumentScannerView(", "startScan()", "fullScreenCover", "addScannedImages"]),
    ("扫描页进入 PhotoItem 流程", "Sources/Services/PhotoStore.swift",
     ["addScannedImages", "origin: .scan", "applyScanDefaultsIfNeeded", "scanFileName"]),
    ("滤镜缩略图（串行渲染）", "Sources/Services/PhotoStore.swift",
     ["filteredThumbnails", "refreshDisplayThumbnails", "ImageEnhancer.apply"]),
    ("设置页滤镜选择", "Sources/Views/SettingsView.swift",
     ["ScanFilter.allCases"]),
    ("OCR 结果面板（可复制）", "Sources/Views/OCRSheetView.swift",
     ["UIPasteboard", "textSelection", "复制全部"]),
    ("PDF 按滤镜渲染", "Sources/Services/PDFGenerator.swift",
     ["ImageEnhancer.apply", "filter: ScanFilter"]),
]

# v2.0 新增 API 与最低系统版本（都必须在 iOS 15.0 以内可用）
SCAN_APIS = [
    ("VNDocumentCameraViewController / .isSupported", "VisionKit", "iOS 13.0", "相机扫描：自动找边 + 透视校正 + 多页连拍"),
    ("VNDocumentCameraScan.pageCount / imageOfPage(at:)", "VisionKit", "iOS 13.0", "取每页扫描结果 UIImage"),
    ("VNRecognizeTextRequest（.accurate）", "Vision", "iOS 13.0", "文字识别；语言 zh-Hans + en-US"),
    ("VNImageRequestHandler(cgImage:options:)", "Vision", "iOS 11.0", "把 CGImage 交给 Vision"),
    ("CIFilter：CIColorControls / CIUnsharpMask / CIHighlightShadowAdjust", "Core Image", "iOS 5.0", "增强 / 黑白 / 灰度 滤镜链"),
    ("CIContext.createCGImage(_:from:)", "Core Image", "iOS 10.0", "滤镜结果转回 CGImage（供 PDF 绘制）"),
    ("CIImage.transformed(by:) + CIContext", "Core Image", "iOS 5.0", "OCR 前把旋转页摆正（无 UIKit 依赖）"),
    ("AVCaptureDevice.authorizationStatus / requestAccess", "AVFoundation", "iOS 7.0", "相机权限判断与请求"),
    ("UIViewControllerRepresentable / .fullScreenCover", "SwiftUI", "iOS 14.0", "全屏呈现系统扫描界面"),
    (".textSelection(.enabled)", "SwiftUI", "iOS 15.0", "OCR 文字可长按选中复制"),
    ("UIPasteboard.general.string", "UIKit", "iOS 2.0", "「复制全部」"),
    (".task(id:)", "SwiftUI", "iOS 15.0", "滤镜变化后重新渲染缩略图"),
]

checks: list[dict] = []      # 每条：name / status(PASS/WARN/FAIL) / detail
details: dict[str, list] = {}  # 明细表格数据


def add_check(name: str, status: str, detail: str) -> None:
    checks.append({"name": name, "status": status, "detail": detail})


def rel(path: str) -> str:
    return os.path.relpath(path, BASE_DIR).replace("\\", "/")


def find_files(root: str, suffix: str) -> list[str]:
    result: list[str] = []
    for dirpath, _dirnames, filenames in os.walk(root):
        for name in filenames:
            if name.endswith(suffix):
                result.append(os.path.join(dirpath, name))
    return sorted(result)


# --------------------------------------------------------------------------
# 1. Swift 语法解析
# --------------------------------------------------------------------------
def check_swift_syntax() -> None:
    files = find_files(BASE_DIR, ".swift")
    if not files:
        add_check("Swift 语法解析", "FAIL", "没有找到任何 .swift 文件")
        return

    try:
        import tree_sitter
        import tree_sitter_swift
        from tree_sitter import Language, Parser
    except Exception as exc:  # noqa: BLE001
        add_check("Swift 语法解析", "FAIL", f"无法导入 tree-sitter / tree-sitter-swift：{exc}")
        return

    ts_version = getattr(tree_sitter, "__version__", "unknown")
    try:
        try:
            language = Language(tree_sitter_swift.language())
        except TypeError:
            language = Language(tree_sitter_swift.language(), "swift")
        try:
            parser = Parser(language)
        except TypeError:
            parser = Parser()
            parser.set_language(language)
    except Exception as exc:  # noqa: BLE001
        add_check("Swift 语法解析", "FAIL", f"初始化 Swift 解析器失败：{exc}")
        return

    rows = []
    failed = 0
    total_lines = 0
    total_bytes = 0

    for path in files:
        with open(path, "rb") as handle:
            source = handle.read()
        total_bytes += len(source)
        total_lines += source.count(b"\n") + 1

        tree = parser.parse(source)
        errors: list[str] = []

        stack = [tree.root_node]
        while stack:
            node = stack.pop()
            if node.type == "ERROR":
                errors.append(
                    f"第 {node.start_point[0] + 1} 行: ERROR "
                    f"'{source[node.start_byte:node.end_byte][:40].decode('utf-8', 'replace')}'"
                )
                continue
            if node.is_missing:
                errors.append(f"第 {node.start_point[0] + 1} 行: 缺少 {node.type}")
                continue
            stack.extend(node.children)

        status = "PASS" if not errors else "FAIL"
        if errors:
            failed += 1
        rows.append(
            {
                "file": rel(path),
                "lines": source.count(b"\n") + 1,
                "status": status,
                "errors": errors,
            }
        )

    details["swift"] = rows
    detail = f"{len(files)} 个文件 / {total_lines} 行 / {total_bytes} 字节，语法错误 {failed} 个（tree-sitter {ts_version}）"
    add_check("Swift 语法解析（tree-sitter-swift）", "PASS" if failed == 0 else "FAIL", detail)


# --------------------------------------------------------------------------
# 2. project.yml
# --------------------------------------------------------------------------
def check_project_yml() -> None:
    path = os.path.join(BASE_DIR, "project.yml")
    if not os.path.exists(path):
        add_check("project.yml", "FAIL", "文件不存在")
        return

    try:
        import yaml
    except Exception as exc:  # noqa: BLE001
        add_check("project.yml", "FAIL", f"无法导入 PyYAML：{exc}")
        return

    with open(path, "r", encoding="utf-8") as handle:
        text = handle.read()
    try:
        data = yaml.safe_load(text)
        yaml_version = yaml.__version__
    except Exception as exc:  # noqa: BLE001
        add_check("project.yml", "FAIL", f"YAML 解析失败：{exc}")
        return

    problems: list[str] = []
    if not isinstance(data, dict):
        problems.append("顶层不是字典")
    else:
        if not data.get("name"):
            problems.append("缺少 name")
        targets = data.get("targets") or {}
        target = targets.get("Photo2PDF") if isinstance(targets, dict) else None
        if not isinstance(target, dict):
            problems.append("缺少 targets.Photo2PDF")
        else:
            if target.get("type") != "application":
                problems.append("target type 不是 application")
            if target.get("platform") != "iOS":
                problems.append("platform 不是 iOS")
            if str(target.get("deploymentTarget")) != "15.0":
                problems.append("deploymentTarget 不是 15.0（iOS 15.1 设备装不上）")
            settings = (target.get("settings") or {}).get("base") or {}
            project_settings = (data.get("settings") or {}).get("base") or {}
            if str(project_settings.get("IPHONEOS_DEPLOYMENT_TARGET")) != "15.0":
                problems.append("settings.base.IPHONEOS_DEPLOYMENT_TARGET 不是 15.0")
            options = data.get("options") or {}
            platform_targets = options.get("deploymentTarget") or {}
            if str(platform_targets.get("iOS")) != "15.0":
                problems.append("options.deploymentTarget.iOS 不是 15.0")
            if settings.get("PRODUCT_BUNDLE_IDENTIFIER") in (None, ""):
                problems.append("缺少 PRODUCT_BUNDLE_IDENTIFIER")
            if settings.get("ASSETCATALOG_COMPILER_APPICON_NAME") != "AppIcon":
                problems.append("没有指定 AppIcon")
            if settings.get("ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME") != "AccentColor":
                problems.append("没有指定 AccentColor")
            # v2.0：版本号与相机权限文案
            marketing = str(project_settings.get("MARKETING_VERSION"))
            if marketing != "2.0.0":
                problems.append(f"MARKETING_VERSION 不是 2.0.0（实际 {marketing}）")
            camera_usage = settings.get("INFOPLIST_KEY_NSCameraUsageDescription")
            if not isinstance(camera_usage, str) or not camera_usage.strip():
                problems.append("缺少 INFOPLIST_KEY_NSCameraUsageDescription（没有相机权限文案，真机进扫描会闪退）")
            elif "相机" not in camera_usage:
                problems.append("NSCameraUsageDescription 不是中文文案")
        schemes = data.get("schemes") or {}
        if "Photo2PDF" not in (schemes if isinstance(schemes, dict) else {}):
            problems.append("缺少 scheme Photo2PDF（xcodebuild -scheme 会失败）")

    detail = f"YAML 合法（PyYAML {yaml_version}）；target/scheme/identifier 校验{'通过' if not problems else '有问题'}：" + (
        "OK" if not problems else "；".join(problems)
    )
    add_check("project.yml（XcodeGen 规格）", "PASS" if not problems else "FAIL", detail)

    # 记录关键配置给报告
    if isinstance(data, dict):
        target = (data.get("targets") or {}).get("Photo2PDF") or {}
        settings = (target.get("settings") or {}).get("base") or {}
        details["project"] = [
            {"key": "工程名", "value": data.get("name")},
            {"key": "Bundle ID", "value": settings.get("PRODUCT_BUNDLE_IDENTIFIER")},
            {"key": "版本号", "value": ((data.get("settings") or {}).get("base") or {}).get("MARKETING_VERSION")},
            {"key": "构建号", "value": ((data.get("settings") or {}).get("base") or {}).get("CURRENT_PROJECT_VERSION")},
            {"key": "最低 iOS", "value": target.get("deploymentTarget")},
            {"key": "IPHONEOS_DEPLOYMENT_TARGET", "value": ((data.get("settings") or {}).get("base") or {}).get("IPHONEOS_DEPLOYMENT_TARGET")},
            {"key": "设备", "value": settings.get("TARGETED_DEVICE_FAMILY")},
            {"key": "AppIcon", "value": settings.get("ASSETCATALOG_COMPILER_APPICON_NAME")},
            {"key": "AccentColor", "value": settings.get("ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME")},
            {"key": "Swift 版本", "value": ((data.get("settings") or {}).get("base") or {}).get("SWIFT_VERSION")},
            {"key": "相机权限文案", "value": settings.get("INFOPLIST_KEY_NSCameraUsageDescription")},
            {"key": "Scheme", "value": "Photo2PDF"},
        ]


# --------------------------------------------------------------------------
# 3. GitHub Actions workflow
# --------------------------------------------------------------------------
def check_workflow() -> None:
    workflows_dir = os.path.join(BASE_DIR, ".github", "workflows")
    files = find_files(workflows_dir, ".yml") if os.path.isdir(workflows_dir) else []
    if not files:
        add_check("GitHub Actions workflow", "FAIL", "找不到 .github/workflows/*.yml")
        return

    try:
        import yaml
    except Exception as exc:  # noqa: BLE001
        add_check("GitHub Actions workflow", "FAIL", f"无法导入 PyYAML：{exc}")
        return

    rows = []
    problems: list[str] = []
    for path in files:
        with open(path, "r", encoding="utf-8") as handle:
            raw = handle.read()
        try:
            data = yaml.safe_load(raw)
        except Exception as exc:  # noqa: BLE001
            problems.append(f"{rel(path)}: YAML 解析失败 {exc}")
            continue

        if not isinstance(data, dict):
            problems.append(f"{rel(path)}: 顶层不是字典")
            continue

        # 注意：YAML 1.1 里裸的 on: 会被解析成布尔 True
        triggers = data.get("on", data.get(True))
        jobs = data.get("jobs") or {}
        build = jobs.get("build") if isinstance(jobs, dict) else None

        file_problems: list[str] = []
        if not triggers:
            file_problems.append("缺少 on 触发条件")
        if not isinstance(build, dict):
            file_problems.append("缺少 jobs.build")
        else:
            if build.get("runs-on") != "macos-15":
                file_problems.append(f"runs-on 不是 macos-15（实际 {build.get('runs-on')}）")
            steps = build.get("steps") or []
            joined = json.dumps(steps, ensure_ascii=False)
            if "xcodebuild archive" not in joined:
                file_problems.append("没有 xcodebuild archive 步骤")
            if "CODE_SIGNING_ALLOWED=NO" not in joined:
                file_problems.append("没有关闭代码签名（CODE_SIGNING_ALLOWED=NO）")
            if "Payload" not in joined or "zip" not in joined:
                file_problems.append("没有打包 Payload/*.app -> zip 的步骤")
            if "actions/upload-artifact" not in joined:
                file_problems.append("没有上传 artifact")
            if "workflow_dispatch" not in raw:
                file_problems.append("没有 workflow_dispatch（无法手动点按钮）")

        if file_problems:
            problems.extend([f"{rel(path)}: {p}" for p in file_problems])

        rows.append(
            {
                "file": rel(path),
                "runs_on": (build or {}).get("runs-on") if isinstance(build, dict) else "-",
                "steps": len((build or {}).get("steps") or []) if isinstance(build, dict) else 0,
                "status": "PASS" if not file_problems else "FAIL",
            }
        )

    details["workflow"] = rows
    add_check(
        "GitHub Actions workflow",
        "PASS" if not problems else "FAIL",
        (f"{len(files)} 个 workflow 文件校验通过" if not problems else "；".join(problems)),
    )


# --------------------------------------------------------------------------
# 4. Assets Contents.json
# --------------------------------------------------------------------------
def check_assets() -> None:
    assets_dir = os.path.join(RESOURCES_DIR, "Assets.xcassets")
    if not os.path.isdir(assets_dir):
        add_check("Assets.xcassets", "FAIL", "目录不存在")
        return

    json_files = find_files(assets_dir, ".json")
    rows = []
    problems: list[str] = []

    for path in json_files:
        try:
            with open(path, "r", encoding="utf-8") as handle:
                data = json.load(handle)
        except Exception as exc:  # noqa: BLE001
            problems.append(f"{rel(path)}: JSON 非法 {exc}")
            rows.append({"file": rel(path), "status": "FAIL", "note": str(exc)})
            continue

        note = "合法 JSON"
        status = "PASS"

        if "info" not in data:
            status = "FAIL"
            note = "缺少 info 字段"
            problems.append(f"{rel(path)}: 缺少 info")
        elif "images" in data:
            for image in data.get("images", []):
                filename = image.get("filename")
                if filename:
                    image_path = os.path.join(os.path.dirname(path), filename)
                    if not os.path.exists(image_path):
                        status = "FAIL"
                        note = f"引用的图片不存在：{filename}"
                        problems.append(f"{rel(path)}: {note}")
        elif "colors" in data:
            note = f"颜色定义 {len(data['colors'])} 个"

        rows.append({"file": rel(path), "status": status, "note": note})

    details["assets"] = rows
    add_check("Assets Contents.json", "PASS" if not problems else "FAIL",
              "；".join(problems) if problems else f"{len(json_files)} 个 JSON 文件全部合法（含引用图片存在性检查）")

    # AppIcon 尺寸 / 通道
    icon_path = os.path.join(assets_dir, "AppIcon.appiconset", "AppIcon-1024.png")
    if not os.path.exists(icon_path):
        add_check("AppIcon 1024 PNG", "FAIL", "找不到 AppIcon-1024.png")
        return
    try:
        from PIL import Image
    except Exception:  # noqa: BLE001
        add_check("AppIcon 1024 PNG", "WARN", "未安装 Pillow，跳过像素级检查（文件存在）")
        return

    with Image.open(icon_path) as image:
        size = image.size
        mode = image.mode
        has_alpha = mode in ("RGBA", "LA") or (mode == "P" and "transparency" in image.info)
    ok = size == (1024, 1024) and not has_alpha
    add_check(
        "AppIcon 1024 PNG",
        "PASS" if ok else "FAIL",
        f"{size[0]}x{size[1]}，模式 {mode}，alpha={'有' if has_alpha else '无'}（要求 1024x1024、无 alpha）",
    )


# --------------------------------------------------------------------------
# 5. 代码风险扫描 + iOS 15 兼容扫描 + #available 清单
# --------------------------------------------------------------------------
def _strip_comments(line: str) -> str:
    """去掉行尾注释，避免注释里提到的 API 名被误判"""
    index = line.find("//")
    return line if index < 0 else line[:index]


def check_code_risks() -> None:
    files = find_files(BASE_DIR, ".swift")
    issues: list[dict] = []
    compat_issues: list[dict] = []
    availability_branches: list[dict] = []

    patterns = [
        (re.compile(r"\btry!\s"), "强制 try!（崩溃风险）"),
        (re.compile(r"\bas!\s"), "强制 as!（崩溃风险）"),
        (re.compile(r"\bfatalError\("), "fatalError（会直接崩溃）"),
        (re.compile(r"\bTODO\b|\bFIXME\b|\b未实现\b"), "TODO/FIXME 残留"),
    ]

    api_regexes = []
    for api in IOS16_PLUS_APIS:
        if api.startswith("."):
            # 成员访问：前面允许空白/换行
            api_regexes.append((re.compile(re.escape(api)), api))
        else:
            api_regexes.append((re.compile(r"(?<![\w.])" + re.escape(api)), api))

    available_regex = re.compile(r"#available\(")

    for path in files:
        with open(path, "r", encoding="utf-8") as handle:
            raw_lines = handle.read().splitlines()
        for number, line in enumerate(raw_lines, start=1):
            stripped = line.strip()
            if stripped.startswith("//") or stripped.startswith("*") or stripped.startswith("/*"):
                continue
            code = _strip_comments(line)

            for pattern, label in patterns:
                if pattern.search(code):
                    issues.append({"file": rel(path), "line": number, "issue": label,
                                   "code": stripped[:100]})

            if TWO_PARAM_ONCHANGE.search(code):
                compat_issues.append({"file": rel(path), "line": number,
                                      "issue": "双参数 onChange 是 iOS 17+（应使用单参数版）",
                                      "code": stripped[:100]})

            for regex, api in api_regexes:
                if regex.search(code):
                    compat_issues.append({"file": rel(path), "line": number,
                                          "issue": f"iOS 16+ API：{api}（iOS 15 不可用）",
                                          "code": stripped[:100]})

            for symbol in IOS16_ONLY_SYMBOLS:
                if symbol in code:
                    compat_issues.append({"file": rel(path), "line": number,
                                          "issue": f"iOS 16+ 才有的 SF Symbol：{symbol}",
                                          "code": stripped[:100]})

            if available_regex.search(code):
                availability_branches.append({"file": rel(path), "line": number,
                                              "code": stripped[:100]})

    details["risks"] = issues
    details["compat"] = compat_issues
    details["available"] = availability_branches

    add_check(
        "代码风险扫描（强制解包 / TODO）",
        "PASS" if not issues else "WARN",
        "未发现 try! / as! / fatalError / TODO" if not issues
        else f"发现 {len(issues)} 处需要人工确认（详见下表）",
    )
    add_check(
        "iOS 15 兼容扫描（禁止 iOS 16+ API）",
        "PASS" if not compat_issues else "FAIL",
        "未发现 iOS 16+ 专属 API / SF Symbol / 双参数 onChange"
        if not compat_issues
        else f"发现 {len(compat_issues)} 处 iOS 16+ 写法（详见下表）",
    )
    add_check(
        "版本判断分支（#available）",
        "PASS",
        f"{len(availability_branches)} 处（本项目用「等价 API」而非版本判断，0 处属预期）",
    )


# --------------------------------------------------------------------------
# 6. 强制要求：检查关键文件是否齐全
# --------------------------------------------------------------------------
REQUIRED_FILES = [
    "project.yml",
    "README.md",
    ".github/workflows/build-ipa.yml",
    "scripts/make_ipa.sh",
    "Resources/Assets.xcassets/AppIcon.appiconset/Contents.json",
    "Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png",
    "Resources/Assets.xcassets/AccentColor.colorset/Contents.json",
    "Sources/App/Photo2PDFApp.swift",
    "Sources/Models/PhotoItem.swift",
    "Sources/Models/PDFOptions.swift",
    "Sources/Services/PhotoStore.swift",
    "Sources/Services/PDFGenerator.swift",
    "Sources/Services/PDFGenerationController.swift",
    "Sources/Services/ImageTools.swift",
    "Sources/Services/PhotoFileImporter.swift",
    "Sources/Services/PDFFileDocument.swift",
    "Sources/Views/ContentView.swift",
    "Sources/Views/MultiPhotoPicker.swift",
    "Sources/Views/SettingsView.swift",
    "Sources/Views/PhotoGridCell.swift",
    "Sources/Views/GeneratorFlowView.swift",
    "Sources/Views/ResultView.swift",
    "Sources/Views/ShareSheet.swift",
    "Sources/Views/EmptyStateView.swift",
    "Sources/Views/DocumentScannerView.swift",
    "Sources/Views/OCRSheetView.swift",
    "Sources/Services/ImageEnhancer.swift",
    "Sources/Services/TextRecognizer.swift",
    "Sources/Services/OCRController.swift",
    "docs/SELF-CHECK.md",
]


def check_required_files() -> None:
    missing = [path for path in REQUIRED_FILES if not os.path.exists(os.path.join(BASE_DIR, path))]
    # 自检报告本身在生成后才会存在，这里只提示
    missing = [m for m in missing if m != "docs/SELF-CHECK.md"]
    add_check("交付文件清单", "PASS" if not missing else "FAIL",
              "全部存在" if not missing else "缺失：" + "、".join(missing))


# --------------------------------------------------------------------------
# 6. v2.0 扫描 / 滤镜 / OCR 功能检查
# --------------------------------------------------------------------------
def check_scan_feature() -> None:
    rows = []
    failed = []

    for label, relative_path, markers in SCAN_MARKERS:
        full_path = os.path.join(BASE_DIR, relative_path)
        if not os.path.exists(full_path):
            rows.append({"label": label, "file": relative_path, "status": "FAIL", "note": "文件不存在"})
            failed.append(label)
            continue

        with open(full_path, "r", encoding="utf-8") as handle:
            text = handle.read()

        absent = [marker for marker in markers if marker not in text]
        if absent:
            rows.append({"label": label, "file": relative_path, "status": "FAIL",
                         "note": "缺少：" + "、".join(absent)})
            failed.append(label)
        else:
            rows.append({"label": label, "file": relative_path, "status": "PASS",
                         "note": f"{len(markers)} 个关键写法齐全"})

    details["scan"] = rows
    add_check(
        "扫描 / 滤镜 / OCR 功能检查（v2.0）",
        "PASS" if not failed else "FAIL",
        "VisionKit 扫描 + Core Image 滤镜 + Vision OCR 全部就位"
        if not failed else "缺失：" + "、".join(failed),
    )


# --------------------------------------------------------------------------
# 报告
# --------------------------------------------------------------------------
def build_report() -> str:
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    statuses = {c["status"] for c in checks}
    overall = "FAIL" if "FAIL" in statuses else ("PASS（含警告）" if "WARN" in statuses else "PASS")
    icon = "❌" if "FAIL" in statuses else ("⚠️" if "WARN" in statuses else "✅")

    lines: list[str] = []
    lines.append("# 自检报告（SELF-CHECK）")
    lines.append("")
    lines.append(f"> 生成时间：{now} ｜ 结论：**{icon} {overall}**")
    lines.append(">")
    lines.append("> 本报告由 `scripts/self_check.py` 自动生成，可随时重跑。")
    lines.append("")

    lines.append("## 0. 环境")
    lines.append("")
    lines.append("| 项 | 值 |")
    lines.append("| --- | --- |")
    lines.append(f"| 主机系统 | {platform.platform()} |")
    lines.append(f"| Python | {sys.version.split()[0]} |")
    lines.append("| 工程最低系统 | **iOS 15.0**（用户真机 iOS 15.1） |")
    lines.append(f"| Swift 编译器 | 无（Windows 无法编译 Swift，改用 tree-sitter 语法解析 + 静态 API 扫描） |")
    try:
        import tree_sitter
        ts_version = getattr(tree_sitter, "__version__", "unknown")
    except Exception:  # noqa: BLE001
        ts_version = "未安装"
    lines.append(f"| tree-sitter | {ts_version} |")
    try:
        import tree_sitter_swift  # noqa: F401
        swift_grammar = "已安装"
    except Exception:  # noqa: BLE001
        swift_grammar = "未安装"
    lines.append(f"| tree-sitter-swift | {swift_grammar} |")
    lines.append("")

    lines.append("## 1. 结论汇总")
    lines.append("")
    lines.append("| 检查项 | 结果 | 说明 |")
    lines.append("| --- | --- | --- |")
    for check in checks:
        badge = {"PASS": "✅ PASS", "WARN": "⚠️ WARN", "FAIL": "❌ FAIL"}[check["status"]]
        lines.append(f"| {check['name']} | {badge} | {check['detail']} |")
    lines.append("")

    if "project" in details:
        lines.append("## 2. 工程关键配置")
        lines.append("")
        lines.append("| 配置 | 值 |")
        lines.append("| --- | --- |")
        for row in details["project"]:
            lines.append(f"| {row['key']} | {row['value']} |")
        lines.append("")

    if "swift" in details:
        lines.append("## 3. Swift 文件语法解析明细")
        lines.append("")
        lines.append("| 文件 | 行数 | 结果 |")
        lines.append("| --- | --- | --- |")
        total = 0
        for row in details["swift"]:
            total += row["lines"]
            badge = "✅" if row["status"] == "PASS" else "❌"
            lines.append(f"| `{row['file']}` | {row['lines']} | {badge} {row['status']} |")
        lines.append(f"| **合计** | **{total}** | |")
        lines.append("")

        error_rows = [row for row in details["swift"] if row["errors"]]
        if error_rows:
            lines.append("### 语法错误明细")
            lines.append("")
            for row in error_rows:
                lines.append(f"- `{row['file']}`")
                for error in row["errors"]:
                    lines.append(f"  - {error}")
            lines.append("")

    if "workflow" in details:
        lines.append("## 4. GitHub Actions 校验")
        lines.append("")
        lines.append("| 文件 | runs-on | 步骤数 | 结果 |")
        lines.append("| --- | --- | --- | --- |")
        for row in details["workflow"]:
            badge = "✅" if row["status"] == "PASS" else "❌"
            lines.append(f"| `{row['file']}` | {row['runs_on']} | {row['steps']} | {badge} |")
        lines.append("")

    if "assets" in details:
        lines.append("## 5. 资源文件校验")
        lines.append("")
        lines.append("| 文件 | 结果 | 说明 |")
        lines.append("| --- | --- | --- |")
        for row in details["assets"]:
            badge = "✅" if row["status"] == "PASS" else "❌"
            lines.append(f"| `{row['file']}` | {badge} | {row['note']} |")
        lines.append("")

    if "risks" in details:
        lines.append("## 6. 代码风险扫描（强制解包 / TODO）")
        lines.append("")
        risks = details["risks"]
        if not risks:
            lines.append("未发现 `try!` / `as!` / `fatalError` / `TODO` 残留。")
        else:
            lines.append("| 文件 | 行 | 问题 | 代码 |")
            lines.append("| --- | --- | --- | --- |")
            for row in risks:
                lines.append(f"| `{row['file']}` | {row['line']} | {row['issue']} | `{row['code'].replace('|', '\\|')}` |")
        lines.append("")

    lines.append("## 7. iOS 15 兼容清单（本次改造的核心）")
    lines.append("")
    lines.append("### 7.1 已完成的替代（旧写法 → 新写法 → 最低可用版本）")
    lines.append("")
    lines.append("| 原写法（iOS 16+） | 现在用的写法（iOS 15 可用） | API 最低版本 |")
    lines.append("| --- | --- | --- |")
    for old, new, since in IOS15_SUBSTITUTIONS:
        lines.append(f"| {old} | {new} | {since} |")
    lines.append("")
    lines.append("### 7.2 iOS 16+ 写法扫描结果")
    lines.append("")
    compat = details.get("compat", [])
    if not compat:
        lines.append("✅ 0 处：源码里已经没有 iOS 16/17 专属 API、SF Symbol 或双参数 `onChange`。")
    else:
        lines.append("| 文件 | 行 | 问题 | 代码 |")
        lines.append("| --- | --- | --- | --- |")
        for row in compat:
            lines.append(f"| `{row['file']}` | {row['line']} | {row['issue']} | `{row['code'].replace('|', '\\|')}` |")
    lines.append("")
    lines.append("### 7.3 `#available` 分支清单")
    lines.append("")
    branches = details.get("available", [])
    if not branches:
        lines.append("0 处。本项目**不需要**版本判断：所有改动的 API 在 iOS 15 都有对应实现，")
        lines.append("因此不存在「某个分支没被编到」的风险。以后若要加 iOS 16+ 特性，")
        lines.append("请写成 `if #available(iOS 16.0, *) { 新写法 } else { 现有写法 }`，并保留现有写法。")
    else:
        lines.append("| 文件 | 行 | 代码 |")
        lines.append("| --- | --- | --- |")
        for row in branches:
            lines.append(f"| `{row['file']}` | {row['line']} | `{row['code'].replace('|', '\\|')}` |")
    lines.append("")

    lines.append("## 8. 仍然必须在 macOS / Xcode 上验证的点")
    lines.append("")
    lines.append("语法正确 ≠ 能编译通过。以下内容 Windows 上无法验证，请在 macOS（或 GitHub Actions 日志）里确认：")
    lines.append("")
    lines.append("1. **类型检查与 API 可用性**（最重要）：tree-sitter 只做语法解析。重点确认 iOS 15 部署目标下："
                 "`NavigationView` + `StackNavigationViewStyle()`、`MultiPhotoPicker` 的 `UIViewControllerRepresentable` 实现、"
                 "`PhotoFileImporter` 里的 `withCheckedThrowingContinuation` + `NSItemProvider` 回调、"
                 "`DocumentScannerView` 的 VisionKit 代理、`OCRController` 的 `actor` + Vision 调用是否有类型错误。")
    lines.append("2. **弃用警告**：`NavigationView`、单参数 `onChange(of:perform:)` 在 Xcode 15/16 会报 deprecated warning——"
                 "只是警告，工程已设置 `SWIFT_TREAT_WARNINGS_AS_ERRORS=NO`，不会让构建失败。")
    lines.append("3. **XcodeGen 生成结果**：`xcodegen generate` 是否成功、`IPHONEOS_DEPLOYMENT_TARGET=15.0` 是否写进工程、"
                 "`INFOPLIST_KEY_*` 是否被正确写入 Info.plist（ipa 里 `MinimumOSVersion` 应为 15.0，且含 `NSCameraUsageDescription`）。")
    lines.append("4. **iOS 15.1 真机相机扫描**（VisionKit 在模拟器不可用）：进扫描是否弹相机授权、多页连拍、自动找边/透视校正、"
                 "取消与失败回调；拍完的页面是否进入网格并带上「扫描」标记。")
    lines.append("5. **iOS 15.1 真机上的相册选择**：PHPicker 以 sheet 内嵌呈现是否正常（导航栏在、能多选、能取消）、"
                 "HEIC 照片能否正常导入（`.current` 表示形式）、导入后缩略图方向是否正确。")
    lines.append("6. **滤镜效果与性能**：四个滤镜（原图/增强/黑白/灰度）在真机上的观感是否接近扫描 App；"
                 "切换滤镜时缩略图是否逐张刷新、是否卡顿；60 页时内存峰值（Xcode Debug Navigator）。")
    lines.append("7. **OCR**：iOS 15.1 上 `zh-Hans` 是否被 Vision 接受（识别中文是否正常）、大页面识别耗时、"
                 "「复制全部」是否真的写进剪贴板。")
    lines.append("8. **`CGPDFContext` + 每页 `MediaBox`**：`kCGPDFContextMediaBox` 传入 `CFData(CGRect)` 的做法需要在真机/模拟器上打开生成的 PDF 确认每页尺寸正确。")
    lines.append("9. **PDF 内容方向与滤镜**：坐标翻转（`translate + scale(1, -1)`）后图片是否正立、用户旋转是否顺时针、等比居中是否准确、滤镜后的像素是否进入 PDF——必须实际打开 PDF 肉眼看。")
    lines.append("10. **「存储到文件」/ 分享面板**：iOS 15.1 上 `fileExporter` 与 `UIActivityViewController`（在 sheet 里再弹 sheet）的表现。")
    lines.append("11. **未签名 ipa 打包**：用 GitHub Actions 实际跑一次，确认 `Payload/Photo2PDF.app` → zip → `.ipa` 能被 Sideloadly 接受。")
    lines.append("")

    lines.append("## 9. 已知风险 / 注意事项")
    lines.append("")
    lines.append("1. **VisionKit 模拟器不可用**：`VNDocumentCameraViewController.isSupported` 在模拟器上是 `false`，"
                 "界面里已经据此隐藏「扫描」按钮，只保留「照片」。真机（iOS 15.1）可用。")
    lines.append("2. **相机权限**：首次进扫描会弹系统授权；用户拒绝后走 `DocumentScanner.permissionHint` 提示。"
                 "Info.plist 必须有中文 `NSCameraUsageDescription`，否则真机一进扫描就闪退（project.yml 已配置）。")
    lines.append("3. **iOS 15 相册选择器的呈现方式**：PHPickerViewController 放在 SwiftUI `.sheet` 里（而不是 UIKit 全屏 `present`）。"
                 "这是 iOS 15 社区的标准做法，但在 15.1 上请确认 sheet 是满屏、能正常取消。")
    lines.append("4. **loadFileRepresentation 的临时 URL 生命周期**：该 URL 只在回调内有效，代码已「在回调里立刻复制」。"
                 "若真机上偶发导入失败，会走 `loadDataRepresentation` 兜底（不会丢照片）。")
    lines.append("5. **滤镜内存**：Core Image 处理大图时峰值不低。代码已做到「逐页解码 → 滤镜 → JPEG → 立即释放」，"
                 "缩略图也只在 480px 上做滤镜并串行刷新；若 60 页仍吃紧，可把 PDF 的 `dpi` 降到 300 以下。")
    lines.append("6. **每页独立页面尺寸**依赖 `CGContext.beginPDFPage` 的 `kCGPDFContextMediaBox`（CFData 形式的 CGRect）。若某些阅读器忽略该字段，会退化成统一 A4——功能不受影响，只是「自动」尺寸不精确。")
    lines.append("7. **JPEG 重压缩**：`jpegQuality < 1.0` 时每页会重新编码为 JPEG（体积小）；设为 100% 则走无损内嵌（PDF 明显变大）。这是刻意行为，不是 bug。")
    lines.append("8. **临时目录**：导入的原图放在 `tmp/Photo2PDF-Sources`，每次启动清空；App 不做持久化，杀掉进程后需要重新选照片。")
    lines.append("9. **免费 Apple ID 限制**：7 天签名、最多 3 个自签 App、每 7 天最多 10 个 App ID——这些是 Apple 侧限制，与本工程无关。")
    lines.append("")

    lines.append("## 10. 最可能编译失败的 3 个点（在 macOS 上优先看这里）")
    lines.append("")
    lines.append("1. **VisionKit / Vision 的代理与类型**：`DocumentScannerView` 的 Coordinator 要实现 "
                 "`documentCameraViewController(_:didFinishWith:)` / `...DidCancel` / `...didFailWithError:`；"
                 "`VNRecognizeTextRequest` 的 `recognitionLevel` 是 `VNRequestTextRecognitionLevel` 枚举（`.accurate`）。"
                 "这些 API 都是 iOS 13 起，已按文档核对；若 Xcode 报代理方法名不匹配，直接按报错提示的签名改。")
    lines.append("2. **SwiftUI 类型推断**：新增的 `EmptyStateView` 用 `pickButton` 复用了同一个 Button；"
                 "如果出现 `some View` 推断失败，把该处拆成显式分支（`if showsScanButton { ... } else { ... }`）即可，"
                 "业务逻辑不用动。")
    lines.append("3. **Core Image / CoreFoundation 细节**：`CIFilter(name:)` + KVC 的写法是 iOS 5 起的老接口，最稳；"
                 "若 `CIContext.createCGImage` 在没有有效 extent 时报错，代码已用 `cropped(to:)` + `extent` 保护。"
                 "PDF 里的 `NSMutableData as CFMutableData` / `Data as CFData` 若报桥接错误，按上一版报告的兜底写法改即可。")
    lines.append("")

    lines.append("## 11. 扫描功能检查（v2.0 新增）")
    lines.append("")
    lines.append("### 11.1 关键实现检查")
    lines.append("")
    lines.append("| 检查项 | 文件 | 结果 | 说明 |")
    lines.append("| --- | --- | --- | --- |")
    for row in details.get("scan", []):
        badge = "✅" if row["status"] == "PASS" else "❌"
        lines.append(f"| {row['label']} | `{row['file']}` | {badge} | {row['note']} |")
    lines.append("")
    lines.append("### 11.2 新增 API 与最低版本（都 ≤ iOS 15.0，不需要 #available）")
    lines.append("")
    lines.append("| API | 框架 | 最低版本 | 用途 |")
    lines.append("| --- | --- | --- | --- |")
    for api, framework, since, purpose in SCAN_APIS:
        lines.append(f"| `{api}` | {framework} | {since} | {purpose} |")
    lines.append("")
    lines.append("### 11.3 权限与 Info.plist")
    lines.append("")
    lines.append("- `NSCameraUsageDescription`（中文，project.yml 的 `INFOPLIST_KEY_NSCameraUsageDescription`）：扫描必须，缺失会闪退。")
    lines.append("- `NSPhotoLibraryUsageDescription`（中文，保留用途描述）：PHPicker 本身不需要相册权限，这里保留是为了以后接入 PHAsset。")
    lines.append("- App 只使用相机 + 用户主动选择的照片，不上传任何数据；不申请定位、麦克风、通讯录等无关权限。")
    lines.append("")
    lines.append("### 11.4 扫描 → 滤镜 → PDF 的数据流")
    lines.append("")
    lines.append("```")
    lines.append("VNDocumentCameraViewController  →  [UIImage]（已找边/透视校正）")
    lines.append("        │ addScannedImages()")
    lines.append("        ▼")
    lines.append("临时目录 JPEG（原样保存，非破坏性）→ PhotoItem(origin: .scan)")
    lines.append("        │ 网格缩略图（480px，按当前滤镜渲染，串行 + 缓存）")
    lines.append("        │ 排序 / 旋转 / 删除（复用 v1 逻辑）")
    lines.append("        ▼")
    lines.append("PDFRenderer：逐页解码 → ImageEnhancer 滤镜 → JPEG → CGPDFContext")
    lines.append("        │ 扫描件默认：页面「自动」贴合 + 边距 0 + 文件名 扫描_yyyyMMdd_HHmm")
    lines.append("        ▼")
    lines.append("分享 / 存储到文件 / OCR（Vision 识别文字，可复制）")
    lines.append("```")
    lines.append("")

    lines.append("---")
    lines.append("")
    lines.append("重跑自检：")
    lines.append("")
    lines.append("```powershell")
    lines.append("photo2pdf\\ios\\.venv\\Scripts\\python.exe photo2pdf\\ios\\scripts\\self_check.py")
    lines.append("```")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    # Windows 控制台默认是 GBK，报告里有 emoji，需要先把输出切成 UTF-8
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:  # noqa: BLE001
        pass

    check_required_files()
    check_swift_syntax()
    check_project_yml()
    check_workflow()
    check_assets()
    check_code_risks()
    check_scan_feature()

    report = build_report()
    if "--no-write" not in sys.argv:
        os.makedirs(DOCS_DIR, exist_ok=True)
        with open(REPORT_PATH, "w", encoding="utf-8") as handle:
            handle.write(report)
        print(f"报告已写入: {REPORT_PATH}")

    print(report)

    failed = any(check["status"] == "FAIL" for check in checks)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
