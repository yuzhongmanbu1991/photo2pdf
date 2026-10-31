# 自检报告（SELF-CHECK）

> 生成时间：2026-10-31 21:38:14 ｜ 结论：**✅ PASS**
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
| Swift 语法解析（tree-sitter-swift） | ✅ PASS | 22 个文件 / 3168 行 / 116747 字节，语法错误 0 个（tree-sitter 0.26.0） |
| project.yml（XcodeGen 规格） | ✅ PASS | YAML 合法（PyYAML 6.0.3）；target/scheme/identifier 校验通过：OK |
| GitHub Actions workflow | ✅ PASS | 1 个 workflow 文件校验通过 |
| Assets Contents.json | ✅ PASS | 3 个 JSON 文件全部合法（含引用图片存在性检查） |
| AppIcon 1024 PNG | ✅ PASS | 1024x1024，模式 RGB，alpha=无（要求 1024x1024、无 alpha） |
| 代码风险扫描（强制解包 / TODO） | ✅ PASS | 未发现 try! / as! / fatalError / TODO |
| iOS 15 兼容扫描（禁止 iOS 16+ API） | ✅ PASS | 未发现 iOS 16+ 专属 API / SF Symbol / 双参数 onChange |
| 版本判断分支（#available） | ✅ PASS | 0 处（本项目用「等价 API」而非版本判断，0 处属预期） |
| 扫描 / 滤镜 / OCR 功能检查（v2.0） | ✅ PASS | VisionKit 扫描 + Core Image 滤镜 + Vision OCR 全部就位 |

## 2. 工程关键配置

| 配置 | 值 |
| --- | --- |
| 工程名 | Photo2PDF |
| Bundle ID | com.dsh.photopdf |
| 版本号 | 2.0.0 |
| 构建号 | 2 |
| 最低 iOS | 15.0 |
| IPHONEOS_DEPLOYMENT_TARGET | 15.0 |
| 设备 | 1,2 |
| AppIcon | AppIcon |
| AccentColor | AccentColor |
| Swift 版本 | 5.0 |
| 相机权限文案 | 需要使用相机拍摄纸质文档来生成 PDF。照片只保存在你的手机里，不会上传到任何服务器。 |
| Scheme | Photo2PDF |

## 3. Swift 文件语法解析明细

| 文件 | 行数 | 结果 |
| --- | --- | --- |
| `Sources/App/Photo2PDFApp.swift` | 24 | ✅ PASS |
| `Sources/Models/PDFOptions.swift` | 133 | ✅ PASS |
| `Sources/Models/PhotoItem.swift` | 82 | ✅ PASS |
| `Sources/Services/ImageEnhancer.swift` | 168 | ✅ PASS |
| `Sources/Services/ImageTools.swift` | 109 | ✅ PASS |
| `Sources/Services/OCRController.swift` | 166 | ✅ PASS |
| `Sources/Services/PDFFileDocument.swift` | 33 | ✅ PASS |
| `Sources/Services/PDFGenerationController.swift` | 152 | ✅ PASS |
| `Sources/Services/PDFGenerator.swift` | 335 | ✅ PASS |
| `Sources/Services/PhotoFileImporter.swift` | 167 | ✅ PASS |
| `Sources/Services/PhotoStore.swift` | 297 | ✅ PASS |
| `Sources/Services/TextRecognizer.swift` | 57 | ✅ PASS |
| `Sources/Views/ContentView.swift` | 357 | ✅ PASS |
| `Sources/Views/DocumentScannerView.swift` | 127 | ✅ PASS |
| `Sources/Views/EmptyStateView.swift` | 112 | ✅ PASS |
| `Sources/Views/GeneratorFlowView.swift` | 110 | ✅ PASS |
| `Sources/Views/MultiPhotoPicker.swift` | 77 | ✅ PASS |
| `Sources/Views/OCRSheetView.swift` | 214 | ✅ PASS |
| `Sources/Views/PhotoGridCell.swift` | 134 | ✅ PASS |
| `Sources/Views/ResultView.swift` | 164 | ✅ PASS |
| `Sources/Views/SettingsView.swift` | 126 | ✅ PASS |
| `Sources/Views/ShareSheet.swift` | 24 | ✅ PASS |
| **合计** | **3168** | |

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

1. **类型检查与 API 可用性**（最重要）：tree-sitter 只做语法解析。重点确认 iOS 15 部署目标下：`NavigationView` + `StackNavigationViewStyle()`、`MultiPhotoPicker` 的 `UIViewControllerRepresentable` 实现、`PhotoFileImporter` 里的 `withCheckedThrowingContinuation` + `NSItemProvider` 回调、`DocumentScannerView` 的 VisionKit 代理、`OCRController` 的 `actor` + Vision 调用是否有类型错误。
2. **弃用警告**：`NavigationView`、单参数 `onChange(of:perform:)` 在 Xcode 15/16 会报 deprecated warning——只是警告，工程已设置 `SWIFT_TREAT_WARNINGS_AS_ERRORS=NO`，不会让构建失败。
3. **XcodeGen 生成结果**：`xcodegen generate` 是否成功、`IPHONEOS_DEPLOYMENT_TARGET=15.0` 是否写进工程、`INFOPLIST_KEY_*` 是否被正确写入 Info.plist（ipa 里 `MinimumOSVersion` 应为 15.0，且含 `NSCameraUsageDescription`）。
4. **iOS 15.1 真机相机扫描**（VisionKit 在模拟器不可用）：进扫描是否弹相机授权、多页连拍、自动找边/透视校正、取消与失败回调；拍完的页面是否进入网格并带上「扫描」标记。
5. **iOS 15.1 真机上的相册选择**：PHPicker 以 sheet 内嵌呈现是否正常（导航栏在、能多选、能取消）、HEIC 照片能否正常导入（`.current` 表示形式）、导入后缩略图方向是否正确。
6. **滤镜效果与性能**：四个滤镜（原图/增强/黑白/灰度）在真机上的观感是否接近扫描 App；切换滤镜时缩略图是否逐张刷新、是否卡顿；60 页时内存峰值（Xcode Debug Navigator）。
7. **OCR**：iOS 15.1 上 `zh-Hans` 是否被 Vision 接受（识别中文是否正常）、大页面识别耗时、「复制全部」是否真的写进剪贴板。
8. **`CGPDFContext` + 每页 `MediaBox`**：`kCGPDFContextMediaBox` 传入 `CFData(CGRect)` 的做法需要在真机/模拟器上打开生成的 PDF 确认每页尺寸正确。
9. **PDF 内容方向与滤镜**：坐标翻转（`translate + scale(1, -1)`）后图片是否正立、用户旋转是否顺时针、等比居中是否准确、滤镜后的像素是否进入 PDF——必须实际打开 PDF 肉眼看。
10. **「存储到文件」/ 分享面板**：iOS 15.1 上 `fileExporter` 与 `UIActivityViewController`（在 sheet 里再弹 sheet）的表现。
11. **未签名 ipa 打包**：用 GitHub Actions 实际跑一次，确认 `Payload/Photo2PDF.app` → zip → `.ipa` 能被 Sideloadly 接受。

## 9. 已知风险 / 注意事项

1. **VisionKit 模拟器不可用**：`VNDocumentCameraViewController.isSupported` 在模拟器上是 `false`，界面里已经据此隐藏「扫描」按钮，只保留「照片」。真机（iOS 15.1）可用。
2. **相机权限**：首次进扫描会弹系统授权；用户拒绝后走 `DocumentScanner.permissionHint` 提示。Info.plist 必须有中文 `NSCameraUsageDescription`，否则真机一进扫描就闪退（project.yml 已配置）。
3. **iOS 15 相册选择器的呈现方式**：PHPickerViewController 放在 SwiftUI `.sheet` 里（而不是 UIKit 全屏 `present`）。这是 iOS 15 社区的标准做法，但在 15.1 上请确认 sheet 是满屏、能正常取消。
4. **loadFileRepresentation 的临时 URL 生命周期**：该 URL 只在回调内有效，代码已「在回调里立刻复制」。若真机上偶发导入失败，会走 `loadDataRepresentation` 兜底（不会丢照片）。
5. **滤镜内存**：Core Image 处理大图时峰值不低。代码已做到「逐页解码 → 滤镜 → JPEG → 立即释放」，缩略图也只在 480px 上做滤镜并串行刷新；若 60 页仍吃紧，可把 PDF 的 `dpi` 降到 300 以下。
6. **每页独立页面尺寸**依赖 `CGContext.beginPDFPage` 的 `kCGPDFContextMediaBox`（CFData 形式的 CGRect）。若某些阅读器忽略该字段，会退化成统一 A4——功能不受影响，只是「自动」尺寸不精确。
7. **JPEG 重压缩**：`jpegQuality < 1.0` 时每页会重新编码为 JPEG（体积小）；设为 100% 则走无损内嵌（PDF 明显变大）。这是刻意行为，不是 bug。
8. **临时目录**：导入的原图放在 `tmp/Photo2PDF-Sources`，每次启动清空；App 不做持久化，杀掉进程后需要重新选照片。
9. **免费 Apple ID 限制**：7 天签名、最多 3 个自签 App、每 7 天最多 10 个 App ID——这些是 Apple 侧限制，与本工程无关。

## 10. 最可能编译失败的 3 个点（在 macOS 上优先看这里）

1. **VisionKit / Vision 的代理与类型**：`DocumentScannerView` 的 Coordinator 要实现 `documentCameraViewController(_:didFinishWith:)` / `...DidCancel` / `...didFailWithError:`；`VNRecognizeTextRequest` 的 `recognitionLevel` 是 `VNRequestTextRecognitionLevel` 枚举（`.accurate`）。这些 API 都是 iOS 13 起，已按文档核对；若 Xcode 报代理方法名不匹配，直接按报错提示的签名改。
2. **SwiftUI 类型推断**：新增的 `EmptyStateView` 用 `pickButton` 复用了同一个 Button；如果出现 `some View` 推断失败，把该处拆成显式分支（`if showsScanButton { ... } else { ... }`）即可，业务逻辑不用动。
3. **Core Image / CoreFoundation 细节**：`CIFilter(name:)` + KVC 的写法是 iOS 5 起的老接口，最稳；若 `CIContext.createCGImage` 在没有有效 extent 时报错，代码已用 `cropped(to:)` + `extent` 保护。PDF 里的 `NSMutableData as CFMutableData` / `Data as CFData` 若报桥接错误，按上一版报告的兜底写法改即可。

## 11. 扫描功能检查（v2.0 新增）

### 11.1 关键实现检查

| 检查项 | 文件 | 结果 | 说明 |
| --- | --- | --- | --- |
| 相机扫描（VisionKit 桥接） | `Sources/Views/DocumentScannerView.swift` | ✅ | 5 个关键写法齐全 |
| 相机权限（AVFoundation） | `Sources/Views/DocumentScannerView.swift` | ✅ | 2 个关键写法齐全 |
| OCR 识别（Vision） | `Sources/Services/TextRecognizer.swift` | ✅ | 5 个关键写法齐全 |
| OCR 流程（进度/取消） | `Sources/Services/OCRController.swift` | ✅ | 4 个关键写法齐全 |
| 增强滤镜（Core Image） | `Sources/Services/ImageEnhancer.swift` | ✅ | 5 个关键写法齐全 |
| 扫描入口与全屏呈现 | `Sources/Views/ContentView.swift` | ✅ | 4 个关键写法齐全 |
| 扫描页进入 PhotoItem 流程 | `Sources/Services/PhotoStore.swift` | ✅ | 4 个关键写法齐全 |
| 滤镜缩略图（串行渲染） | `Sources/Services/PhotoStore.swift` | ✅ | 3 个关键写法齐全 |
| 设置页滤镜选择 | `Sources/Views/SettingsView.swift` | ✅ | 1 个关键写法齐全 |
| OCR 结果面板（可复制） | `Sources/Views/OCRSheetView.swift` | ✅ | 3 个关键写法齐全 |
| PDF 按滤镜渲染 | `Sources/Services/PDFGenerator.swift` | ✅ | 2 个关键写法齐全 |

### 11.2 新增 API 与最低版本（都 ≤ iOS 15.0，不需要 #available）

| API | 框架 | 最低版本 | 用途 |
| --- | --- | --- | --- |
| `VNDocumentCameraViewController / .isSupported` | VisionKit | iOS 13.0 | 相机扫描：自动找边 + 透视校正 + 多页连拍 |
| `VNDocumentCameraScan.pageCount / imageOfPage(at:)` | VisionKit | iOS 13.0 | 取每页扫描结果 UIImage |
| `VNRecognizeTextRequest（.accurate）` | Vision | iOS 13.0 | 文字识别；语言 zh-Hans + en-US |
| `VNImageRequestHandler(cgImage:options:)` | Vision | iOS 11.0 | 把 CGImage 交给 Vision |
| `CIFilter：CIColorControls / CIUnsharpMask / CIHighlightShadowAdjust` | Core Image | iOS 5.0 | 增强 / 黑白 / 灰度 滤镜链 |
| `CIContext.createCGImage(_:from:)` | Core Image | iOS 10.0 | 滤镜结果转回 CGImage（供 PDF 绘制） |
| `CIImage.transformed(by:) + CIContext` | Core Image | iOS 5.0 | OCR 前把旋转页摆正（无 UIKit 依赖） |
| `AVCaptureDevice.authorizationStatus / requestAccess` | AVFoundation | iOS 7.0 | 相机权限判断与请求 |
| `UIViewControllerRepresentable / .fullScreenCover` | SwiftUI | iOS 14.0 | 全屏呈现系统扫描界面 |
| `.textSelection(.enabled)` | SwiftUI | iOS 15.0 | OCR 文字可长按选中复制 |
| `UIPasteboard.general.string` | UIKit | iOS 2.0 | 「复制全部」 |
| `.task(id:)` | SwiftUI | iOS 15.0 | 滤镜变化后重新渲染缩略图 |

### 11.3 权限与 Info.plist

- `NSCameraUsageDescription`（中文，project.yml 的 `INFOPLIST_KEY_NSCameraUsageDescription`）：扫描必须，缺失会闪退。
- `NSPhotoLibraryUsageDescription`（中文，保留用途描述）：PHPicker 本身不需要相册权限，这里保留是为了以后接入 PHAsset。
- App 只使用相机 + 用户主动选择的照片，不上传任何数据；不申请定位、麦克风、通讯录等无关权限。

### 11.4 扫描 → 滤镜 → PDF 的数据流

```
VNDocumentCameraViewController  →  [UIImage]（已找边/透视校正）
        │ addScannedImages()
        ▼
临时目录 JPEG（原样保存，非破坏性）→ PhotoItem(origin: .scan)
        │ 网格缩略图（480px，按当前滤镜渲染，串行 + 缓存）
        │ 排序 / 旋转 / 删除（复用 v1 逻辑）
        ▼
PDFRenderer：逐页解码 → ImageEnhancer 滤镜 → JPEG → CGPDFContext
        │ 扫描件默认：页面「自动」贴合 + 边距 0 + 文件名 扫描_yyyyMMdd_HHmm
        ▼
分享 / 存储到文件 / OCR（Vision 识别文字，可复制）
```

---

重跑自检：

```powershell
photo2pdf\ios\.venv\Scripts\python.exe photo2pdf\ios\scripts\self_check.py
```
