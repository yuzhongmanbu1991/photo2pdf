# 自检报告（SELF-CHECK）

> 生成时间：2026-10-31 21:09:26 ｜ 结论：**✅ PASS**
>
> 本报告由 `scripts/self_check.py` 自动生成，可随时重跑。

## 0. 环境

| 项 | 值 |
| --- | --- |
| 主机系统 | Windows-10-10.0.19045-SP0 |
| Python | 3.12.9 |
| 工程最低系统 | **iOS 15.0**（用户真机 iOS 15.1） |
| Swift 编译器 | 无（Windows 无法编译 Swift，改用 tree-sitter 语法解析 + 静态 API 扫描） |
| tree-sitter | 0.26.0 |
| tree-sitter-swift | 已安装 |

## 1. 结论汇总

| 检查项 | 结果 | 说明 |
| --- | --- | --- |
| 交付文件清单 | ✅ PASS | 全部存在 |
| Swift 语法解析（tree-sitter-swift） | ✅ PASS | 17 个文件 / 2065 行 / 74504 字节，语法错误 0 个（tree-sitter 0.26.0） |
| project.yml（XcodeGen 规格） | ✅ PASS | YAML 合法（PyYAML 6.0.3）；target/scheme/identifier 校验通过：OK |
| GitHub Actions workflow | ✅ PASS | 1 个 workflow 文件校验通过 |
| Assets Contents.json | ✅ PASS | 3 个 JSON 文件全部合法（含引用图片存在性检查） |
| AppIcon 1024 PNG | ✅ PASS | 1024x1024，模式 RGB，alpha=无（要求 1024x1024、无 alpha） |
| 代码风险扫描（强制解包 / TODO） | ✅ PASS | 未发现 try! / as! / fatalError / TODO |
| iOS 15 兼容扫描（禁止 iOS 16+ API） | ✅ PASS | 未发现 iOS 16+ 专属 API / SF Symbol / 双参数 onChange |
| 版本判断分支（#available） | ✅ PASS | 0 处（本项目用「等价 API」而非版本判断，0 处属预期） |

## 2. 工程关键配置

| 配置 | 值 |
| --- | --- |
| 工程名 | Photo2PDF |
| Bundle ID | com.dsh.photopdf |
| 最低 iOS | 15.0 |
| IPHONEOS_DEPLOYMENT_TARGET | 15.0 |
| 设备 | 1,2 |
| AppIcon | AppIcon |
| AccentColor | AccentColor |
| Swift 版本 | 5.0 |
| Scheme | Photo2PDF |

## 3. Swift 文件语法解析明细

| 文件 | 行数 | 结果 |
| --- | --- | --- |
| `Sources/App/Photo2PDFApp.swift` | 24 | ✅ PASS |
| `Sources/Models/PDFOptions.swift` | 123 | ✅ PASS |
| `Sources/Models/PhotoItem.swift` | 67 | ✅ PASS |
| `Sources/Services/ImageTools.swift` | 109 | ✅ PASS |
| `Sources/Services/PDFFileDocument.swift` | 33 | ✅ PASS |
| `Sources/Services/PDFGenerationController.swift` | 146 | ✅ PASS |
| `Sources/Services/PDFGenerator.swift` | 324 | ✅ PASS |
| `Sources/Services/PhotoFileImporter.swift` | 167 | ✅ PASS |
| `Sources/Services/PhotoStore.swift` | 140 | ✅ PASS |
| `Sources/Views/ContentView.swift` | 287 | ✅ PASS |
| `Sources/Views/EmptyStateView.swift` | 83 | ✅ PASS |
| `Sources/Views/GeneratorFlowView.swift` | 110 | ✅ PASS |
| `Sources/Views/MultiPhotoPicker.swift` | 77 | ✅ PASS |
| `Sources/Views/PhotoGridCell.swift` | 113 | ✅ PASS |
| `Sources/Views/ResultView.swift` | 129 | ✅ PASS |
| `Sources/Views/SettingsView.swift` | 109 | ✅ PASS |
| `Sources/Views/ShareSheet.swift` | 24 | ✅ PASS |
| **合计** | **2065** | |

## 4. GitHub Actions 校验

| 文件 | runs-on | 步骤数 | 结果 |
| --- | --- | --- | --- |
| `.github/workflows/build-ipa.yml` | macos-15 | 10 | ✅ |

## 5. 资源文件校验

| 文件 | 结果 | 说明 |
| --- | --- | --- |
| `Resources/Assets.xcassets/AccentColor.colorset/Contents.json` | ✅ | 颜色定义 2 个 |
| `Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` | ✅ | 合法 JSON |
| `Resources/Assets.xcassets/Contents.json` | ✅ | 合法 JSON |

## 6. 代码风险扫描（强制解包 / TODO）

未发现 `try!` / `as!` / `fatalError` / `TODO` 残留。

## 7. iOS 15 兼容清单（本次改造的核心）

### 7.1 已完成的替代（旧写法 → 新写法 → 最低可用版本）

| 原写法（iOS 16+） | 现在用的写法（iOS 15 可用） | API 最低版本 |
| --- | --- | --- |
| NavigationStack | NavigationView + StackNavigationViewStyle()（iOS 13） | iOS 13 |
| PhotosPicker / PhotosPickerItem | MultiPhotoPicker（PHPickerViewController 桥接） | iOS 14 |
| PHPickerConfiguration.preferredAssetRepresentationMode | = .current，HEIC 保持原格式 | iOS 14 |
| NSItemProvider.loadTransferable（异步取 Data） | loadFileRepresentation 优先 / loadDataRepresentation 兜底 | iOS 11 |
| .presentationDetents([.medium, .large]) | 删除，sheet 用系统默认高度 | - |
| ShareLink | ShareSheet（UIActivityViewController） | iOS 13 |
| Grid / GridItem（Grid 容器） | LazyVGrid + GridItem（本项目一直用的就是它） | iOS 14 |
| SF Symbol photo.badge.plus | photo.on.rectangle | iOS 14 |
| SF Symbol doc.badge.arrow.up | doc.text | iOS 13 |
| iOS 17 双参数 onChange | iOS 14 单参数 onChange(of:) { newValue in } | iOS 14 |

### 7.2 iOS 16+ 写法扫描结果

✅ 0 处：源码里已经没有 iOS 16/17 专属 API、SF Symbol 或双参数 `onChange`。

### 7.3 `#available` 分支清单

0 处。本项目**不需要**版本判断：所有改动的 API 在 iOS 15 都有对应实现，
因此不存在「某个分支没被编到」的风险。以后若要加 iOS 16+ 特性，
请写成 `if #available(iOS 16.0, *) { 新写法 } else { 现有写法 }`，并保留现有写法。

## 8. 仍然必须在 macOS / Xcode 上验证的点

语法正确 ≠ 能编译通过。以下内容 Windows 上无法验证，请在 macOS（或 GitHub Actions 日志）里确认：

1. **类型检查与 API 可用性**（最重要）：tree-sitter 只做语法解析。重点确认 iOS 15 部署目标下：`NavigationView` + `StackNavigationViewStyle()`、`MultiPhotoPicker` 的 `UIViewControllerRepresentable` 实现、`PhotoFileImporter` 里的 `withCheckedThrowingContinuation` + `NSItemProvider` 回调是否有类型错误。
2. **弃用警告**：`NavigationView`、单参数 `onChange(of:perform:)` 在 Xcode 15/16 会报 deprecated warning——只是警告，工程已设置 `SWIFT_TREAT_WARNINGS_AS_ERRORS=NO`，不会让构建失败。
3. **XcodeGen 生成结果**：`xcodegen generate` 是否成功、`IPHONEOS_DEPLOYMENT_TARGET=15.0` 是否写进工程、`INFOPLIST_KEY_*` 是否被正确写入 Info.plist（生成的 ipa 里 `MinimumOSVersion` 应为 15.0）。
4. **iOS 15.1 真机上的相册选择**：PHPicker 以 sheet 内嵌呈现是否正常（导航栏在、能多选、能取消）、HEIC 照片能否正常导入（`.current` 表示形式）、导入后缩略图方向是否正确。
5. **`CGPDFContext` + 每页 `MediaBox`**：`kCGPDFContextMediaBox` 传入 `CFData(CGRect)` 的做法需要在真机/模拟器上打开生成的 PDF 确认每页尺寸正确。
6. **PDF 内容方向**：坐标翻转（`translate + scale(1, -1)`）后图片是否正立、用户旋转是否顺时针、等比居中是否准确——必须实际打开 PDF 肉眼看。
7. **内存峰值**：`Xcode → Debug Navigator → Memory` 观察 60 张 1200 万像素照片的生成过程，确认 iOS 15.1 设备（可能是 4GB 内存）没有被打爆。
8. **「存储到文件」/ 分享面板**：iOS 15.1 上 `fileExporter` 与 `UIActivityViewController`（在 sheet 里再弹 sheet）的表现。
9. **未签名 ipa 打包**：用 GitHub Actions 实际跑一次，确认 `Payload/Photo2PDF.app` → zip → `.ipa` 能被 Sideloadly 接受。

## 9. 已知风险 / 注意事项

1. **iOS 15 相册选择器的呈现方式**：PHPickerViewController 放在 SwiftUI `.sheet` 里（而不是 UIKit 全屏 `present`）。这是 iOS 15 社区的标准做法，但在 15.1 上请确认 sheet 是满屏、能正常取消；若发现样式异常，可改成用 `UIApplication` 拿顶层 `UIViewController` 全屏 present（`PhotoFileImporter` / `MultiPhotoPicker` 的接口不用变，只改呈现方式）。
2. **loadFileRepresentation 的临时 URL 生命周期**：该 URL 只在回调内有效，代码已「在回调里立刻复制」。若真机上偶发导入失败，会走 `loadDataRepresentation` 兜底（不会丢照片）。
3. **每页独立页面尺寸**依赖 `CGContext.beginPDFPage` 的 `kCGPDFContextMediaBox`（CFData 形式的 CGRect）。若某些阅读器忽略该字段，会退化成统一 A4——功能不受影响，只是「自动」尺寸不精确。
4. **JPEG 重压缩**：`jpegQuality < 1.0` 时每页会重新编码为 JPEG（体积小）；设为 100% 则走无损内嵌（PDF 明显变大）。这是刻意行为，不是 bug。
5. **临时目录**：导入的原图放在 `tmp/Photo2PDF-Sources`，每次启动清空；App 不做持久化，杀掉进程后需要重新选照片。
6. **免费 Apple ID 限制**：7 天签名、最多 3 个自签 App、每 7 天最多 10 个 App ID——这些是 Apple 侧限制，与本工程无关。
7. **iOS 15.1 是老系统**：Xcode 16 的 iOS 18 SDK 允许部署到 15.0，但真机行为只能以 iOS 15.1 为准；尤其是「存储到文件」面板、分享面板这些系统 UI 的文案/样式会与 iOS 17/18 略有差别。

## 10. 最可能编译失败的 3 个点（在 macOS 上优先看这里）

1. **iOS 15 不可用 API 漏网**：最典型的是 `NavigationView`/`NavigationStack` 混用、`PhotosPicker` 残留、`.presentationDetents`、`ShareLink`。本报告第 7.2 节已用脚本扫过（0 处），但仍建议在 Xcode 里 `Product → Build` 后看有没有 `only available in iOS 16.0 or newer` 的报错——有的话直接把该行换成第 7.1 节的写法。
2. **CoreFoundation 桥接**：`CGDataConsumer(data: pdfData as CFMutableData)` 与 `kCGPDFContextMediaBox: cgRectData(...)`（`Data as CFData`）。如果 Xcode 报 `cannot convert value of type 'NSMutableData' to type 'CFMutableData'`，把 `PDFGenerator.swift` 里的 `NSMutableData` 换成 `CFDataCreateMutable(nil, 0)`，最后用 `Data(referencing:)`/`(pdfData as NSData) as Data` 取回字节即可（逻辑不变）。
3. **PHPicker 桥接的类型细节**：`withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in ... }` 在回调里 resume；若报 `Escaping closure captures non-escaping parameter 'continuation'` 之类，检查是否把 continuation 传进了嵌套函数；`PHPickerConfiguration()` / `preferredAssetRepresentationMode` 均为 iOS 14 API，已核对文档。

---

重跑自检：

```powershell
photo2pdf\ios\.venv\Scripts\python.exe photo2pdf\ios\scripts\self_check.py
```
