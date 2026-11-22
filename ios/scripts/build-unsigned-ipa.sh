#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# 生成【未签名】IPA。全程不需要任何证书 / Team ID / provisioning profile。
#
# 产物: ios/build/CyIME-unsigned.ipa
# 之后由你自己用 3uTools / 爱思助手 / 轻松签(ESign) / Sideloadly / iOS App Signer
# 加上企业证书(.p12 + .mobileprovision)手动签名并安装。
#
# 用法（在 macOS 上）:
#   brew install xcodegen          # 若未安装
#   ./scripts/build-unsigned-ipa.sh
#
# 可选环境变量: SCHEME / CONFIGURATION / DEPLOY_TARGET / BUILD_DIR
# ---------------------------------------------------------------------------
set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="${SCHEME:-CyIME}"
CONFIGURATION="${CONFIGURATION:-Release}"
DEPLOY_TARGET="${DEPLOY_TARGET:-26.0}"
BUILD_DIR="${BUILD_DIR:-build}"
ARCHIVE_PATH="$BUILD_DIR/CyIME.xcarchive"
IPA_PATH="$BUILD_DIR/CyIME-unsigned.ipa"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "错误: 未找到 xcodebuild。本脚本必须在 macOS + Xcode 上运行。" >&2
  exit 1
fi
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "错误: 未找到 xcodegen。请先执行: brew install xcodegen" >&2
  exit 1
fi

echo "==> 生成 Xcode 工程"
xcodegen generate

echo "==> 归档（不签名）"
rm -rf "$ARCHIVE_PATH" "$BUILD_DIR/ipa" "$IPA_PATH"
mkdir -p "$BUILD_DIR"
xcodebuild archive \
  -project CyIME.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  -destination 'generic/platform=iOS' \
  IPHONEOS_DEPLOYMENT_TARGET="$DEPLOY_TARGET" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  EXPANDED_CODE_SIGN_IDENTITY="" \
  ONLY_ACTIVE_ARCH=NO

APP_PATH="$ARCHIVE_PATH/Products/Applications/CyIME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "错误: 归档中未找到 CyIME.app -> $APP_PATH" >&2
  exit 1
fi

echo "==> 打包 Payload"
mkdir -p "$BUILD_DIR/ipa/Payload"
ditto "$APP_PATH" "$BUILD_DIR/ipa/Payload/CyIME.app"

if [[ -d "$BUILD_DIR/ipa/Payload/CyIME.app/PlugIns/CyIMEKeyboard.appex" ]]; then
  echo "    已包含键盘扩展: CyIMEKeyboard.appex"
else
  echo "    警告: 未找到 CyIMEKeyboard.appex，请检查 project.yml 的 embed 配置" >&2
fi

( cd "$BUILD_DIR/ipa" && zip -qry "../CyIME-unsigned.ipa" Payload )
rm -rf "$BUILD_DIR/ipa"

echo "==> 完成: $IPA_PATH"
ls -lh "$IPA_PATH"
echo "SHA256: $(shasum -a 256 "$IPA_PATH" | awk '{print $1}')"
