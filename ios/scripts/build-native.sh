#!/usr/bin/env bash
# 构建 CyIME 的 iOS 原生静态库 libCyIMERime.a（librime + 依赖 + CyIME 自定义 C++）。
# 仅在 macOS + Xcode 上运行。产出：ios/native/lib/libCyIMERime.a。
#
# 用法：
#   cd ios && ./scripts/build-native.sh
#
# 注意：第一版草稿，未在 macOS 上验证，需按报错迭代。
set -euo pipefail

cd "$(dirname "$0")/.."   # 进入 ios/

REPO_ROOT="$(cd .. && pwd)"
JNI_DIR="$REPO_ROOT/app/src/main/jni"
NATIVE_DIR="$PWD/native"
BUILD_DIR="$NATIVE_DIR/build"
OUT_DIR="$NATIVE_DIR/lib"

echo "==> 初始化子模块"
(cd "$REPO_ROOT" && git submodule update --init --recursive)

echo "==> 检查 Xcode"
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "错误: 未找到 xcodebuild，请在 macOS 上运行。" >&2
  exit 1
fi
xcodebuild -version

echo "==> CMake 配置"
rm -rf "$BUILD_DIR"
cmake -S "$NATIVE_DIR" -B "$BUILD_DIR" \
  -DCMAKE_TOOLCHAIN_FILE="$NATIVE_DIR/ios.toolchain.cmake" \
  -DCYIME_JNI_DIR="$JNI_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF

echo "==> 编译"
cmake --build "$BUILD_DIR" --config Release -- -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

echo "==> 合并静态库 -> libCyIMERime.a"
mkdir -p "$OUT_DIR"
# -force_load 需要整库都载入（保证 RIME_REGISTER_MODULE 的静态构造器不被裁掉），
# 所以把所有 .a 合并成一个，再在 Xcode 里 -force_load 这一个。
mapfile -t LIBS < <(find "$BUILD_DIR" -name '*.a' ! -name '*gtest*' ! -name '*benchmark*' | sort)
if [ "${#LIBS[@]}" -eq 0 ]; then
  echo "错误: 没有找到任何 .a 文件" >&2
  exit 1
fi
echo "合并以下库："
printf '  %s\n' "${LIBS[@]}"
libtool -static -o "$OUT_DIR/libCyIMERime.a" "${LIBS[@]}"

echo "==> 完成"
ls -lh "$OUT_DIR/libCyIMERime.a"
