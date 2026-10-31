#!/usr/bin/env bash
#
# 本地一键打包（必须在 macOS 上运行，需要 Xcode 命令行工具）
#
# 用法：
#   ./scripts/make_ipa.sh              # 生成未签名 ipa，输出到 build/Photo2PDF-unsigned.ipa
#   ./scripts/make_ipa.sh --open       # 打包完成后打开 build 目录
#   ./scripts/make_ipa.sh --run        # 打包后在当前已连接的设备上直接运行（需开发者签名）
#
# 说明：
#   * 未签名 ipa 不能直接安装到 iPhone，需要用 Sideloadly / AltStore 用自己的 Apple ID 重签；
#   * 如果你有开发者账号并想直接装到自己的设备上，用 --run 走正常的签名归档流程，
#     同时把 project.yml 里的 DEVELOPMENT_TEAM 填上你的 Team ID。
#
set -euo pipefail

# ---------- 定位目录 ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

APP_NAME="Photo2PDF"
SCHEME="Photo2PDF"
PROJECT="Photo2PDF.xcodeproj"
BUILD_DIR="$PROJECT_ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
IPA_PATH="$BUILD_DIR/$APP_NAME-unsigned.ipa"

OPEN_AFTER=0
RUN_ON_DEVICE=0
for arg in "$@"; do
  case "$arg" in
    --open) OPEN_AFTER=1 ;;
    --run) RUN_ON_DEVICE=1 ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *)
      echo "未知参数: $arg" >&2
      exit 2
      ;;
  esac
done

# ---------- 环境检查 ----------
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "错误：本脚本只能在 macOS 上运行（需要 Xcode）。" >&2
  echo "      没有 Mac？用 GitHub Actions：见 README.md 的「方式一」。" >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "错误：没有找到 xcodebuild，请先安装 Xcode 或 Command Line Tools。" >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "==> 未安装 XcodeGen，尝试用 Homebrew 安装…"
  if command -v brew >/dev/null 2>&1; then
    brew install xcodegen
  else
    echo "错误：没有 Homebrew 也没有 XcodeGen。请先安装其中一个：" >&2
    echo "      /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"" >&2
    exit 1
  fi
fi

# ---------- 生成工程 ----------
echo "==> 生成 Xcode 工程"
xcodegen generate --spec project.yml

mkdir -p "$BUILD_DIR"

# ---------- 归档 ----------
echo "==> 归档（Release）"
if [[ "$RUN_ON_DEVICE" -eq 1 ]]; then
  # 走正常签名流程（需要有开发者账号 / 已在设备上登录 Xcode）
  xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates
else
  # 关闭签名：产出可直接被 Sideloadly / AltStore 重签的未签名包
  xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    DEVELOPMENT_TEAM=""
fi

APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "错误：归档里没有找到 $APP_NAME.app" >&2
  exit 1
fi

# ---------- 打包 ipa ----------
if [[ "$RUN_ON_DEVICE" -eq 0 ]]; then
  echo "==> 打包未签名 ipa"
  STAGE_DIR="$BUILD_DIR/ipa-stage"
  rm -rf "$STAGE_DIR"
  mkdir -p "$STAGE_DIR/Payload"
  cp -R "$APP_PATH" "$STAGE_DIR/Payload/"
  rm -rf "$STAGE_DIR/Payload/$APP_NAME.app/_CodeSignature"
  ( cd "$STAGE_DIR" && /usr/bin/zip -r -q -y "$IPA_PATH" Payload )
  rm -rf "$STAGE_DIR"
  echo "==> 完成：$IPA_PATH ($(du -h "$IPA_PATH" | cut -f1))"
  echo "    用 Sideloadly / AltStore 打开这个 ipa，登录你的 Apple ID 即可安装。"
else
  echo "==> 完成：$ARCHIVE_PATH"
  echo "    可打开 Xcode -> Window -> Organizer 选择设备安装。"
fi

if [[ "$OPEN_AFTER" -eq 1 ]]; then
  open "$BUILD_DIR"
fi
