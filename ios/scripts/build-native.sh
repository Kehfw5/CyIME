#!/usr/bin/env bash
# 构建 CyIME 的 iOS 原生静态库 libCyIMERime.a（librime + 依赖 + CyIME 自定义 C++）。
# 仅在 macOS + Xcode 上运行（本地 Mac 或 GitHub Actions 的 macos runner）。
# 产出：ios/native/lib/libCyIMERime.a
#
# 用法：
#   cd ios && ./scripts/build-native.sh
# 可选环境变量：
#   DEPLOY_TARGET   部署目标，默认 26.0
#   JOBS            并行数，默认 CPU 核数
set -euo pipefail

cd "$(dirname "$0")/.."   # 进入 ios/

REPO_ROOT="$(cd .. && pwd)"
JNI_DIR="$REPO_ROOT/app/src/main/jni"
NATIVE_DIR="$PWD/native"
BUILD_DIR="$NATIVE_DIR/build"
OUT_DIR="$NATIVE_DIR/lib"
DEPLOY_TARGET="${DEPLOY_TARGET:-26.0}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"

echo "==> 初始化子模块"
(cd "$REPO_ROOT" && git submodule update --init --recursive)

echo "==> 检查工具链"
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "错误: 未找到 xcodebuild，请在 macOS 上运行。" >&2
  exit 1
fi
xcodebuild -version
if ! command -v cmake >/dev/null 2>&1; then
  echo "==> 安装 cmake"
  brew install cmake
fi
cmake --version | head -1

echo "==> CMake 配置 (DEPLOY_TARGET=$DEPLOY_TARGET)"
rm -rf "$BUILD_DIR"
cmake -S "$NATIVE_DIR" -B "$BUILD_DIR" \
  -DCMAKE_TOOLCHAIN_FILE="$NATIVE_DIR/ios.toolchain.cmake" \
  -DCYIME_JNI_DIR="$JNI_DIR" \
  -DCYIME_IOS_DEPLOYMENT_TARGET="$DEPLOY_TARGET" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF

echo "==> 编译 (-j$JOBS)"
# 只构建 rime-static，不构建 ALL：
#  - opencc 的 data 目标（ALL）会运行刚编出的 iOS 版 opencc_dict 生成 .ocd2，
#    iOS 二进制在 macOS 上无法执行（Error 127）。Rime 自己带 opencc 数据，用不到它。
#  - 这样也跳过 leveldbutil / opencc 等我们用不上的命令行工具。
cmake --build "$BUILD_DIR" --config Release --target rime-static -- -j"$JOBS"

echo "==> 合并静态库 -> libCyIMERime.a"
mkdir -p "$OUT_DIR"
# 收集所有 .a（排除测试/基准库）。-force_load 需要整库载入，所以先合并成一个。
LIBS=()
while IFS= read -r lib; do
  [ -z "$lib" ] && continue
  LIBS+=("$lib")
done < <(find "$BUILD_DIR" -name '*.a' \
  ! -name '*gtest*' ! -name '*gmock*' ! -name '*benchmark*' | sort)

if [ "${#LIBS[@]}" -eq 0 ]; then
  echo "错误: 没有找到任何 .a 文件" >&2
  exit 1
fi
echo "合并以下 ${#LIBS[@]} 个库："
printf '  %s\n' "${LIBS[@]}"
libtool -static -o "$OUT_DIR/libCyIMERime.a" "${LIBS[@]}"

echo "==> 完成"
ls -lh "$OUT_DIR/libCyIMERime.a"
