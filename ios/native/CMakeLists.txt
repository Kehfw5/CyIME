cmake_minimum_required(VERSION 3.18.0)

# 自包含的 iOS 构建入口：复用 Android（app/src/main/jni）里的 librime 源码与依赖，
# 但把 Android-only 的 JNI/ONNX 目标剥掉，并去掉 onnxruntime 依赖（CyLM/ONNX 重排器
# 在 Android 里本就默认关闭、35MB 模型也不打包）。
#
# 注意：本文件是第一版草稿，未在 macOS 上验证过，需要在 Mac 上迭代。
# 调用方是 ios/scripts/build-native.sh。

if(NOT DEFINED CYIME_JNI_DIR)
  message(FATAL_ERROR "CYIME_JNI_DIR must point at app/src/main/jni")
endif()

# 让 cmake/ 下的 helper（Boost/Rime/OpenccWorkarounds/FindBoost）把源码根
# 定位到 jni 目录，复用与 Android 完全相同的补丁/依赖/插件构建逻辑。
set(CYIME_ROOT "${CYIME_JNI_DIR}")

# ---- iOS 平台 ----
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
option(BUILD_SHARED_LIBS "" OFF)
option(BUILD_TESTING "" OFF)
option(BUILD_STATIC "" ON)
# librime 默认 BUILD_TEST=ON 会 find_package(GTest REQUIRED)；iOS 不跑测试。
option(BUILD_TEST "" OFF)
# octagram 插件默认会编译命令行工具（可执行文件）；iOS 静态库不需要。
set(BUILD_TOOLS OFF CACHE BOOL "" FORCE)

# 去掉绝对路径，保证产物与构建机无关（与 Android 构建保持一致）。
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -ffile-prefix-map=${CYIME_JNI_DIR}=")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -ffile-prefix-map=${CYIME_JNI_DIR}=")

# ---- 复用 Android 的补丁 / 插件 / 依赖构建逻辑 ----
set(CMAKE_MODULE_PATH "${CYIME_JNI_DIR}/cmake" ${CMAKE_MODULE_PATH})

# Boost：下载 1.89.0（header-only）。复用 Android 的 Boost.cmake，
# 其内部通过 CYIME_ROOT 定位源码根（上面已设 CYIME_ROOT=JNI 目录）。
include(Boost)

# glog
option(WITH_GFLAGS "Use gflags" OFF)
option(WITH_GTEST "Use googletest" OFF)
set(WITH_UNWIND "none" CACHE STRING "Enable libunwind support (values: none, unwind, libunwind)")
add_subdirectory("${CYIME_JNI_DIR}/librime/deps/glog" "${CMAKE_BINARY_DIR}/librime/deps/glog")
target_compile_options(glog_internal PRIVATE "-ffile-prefix-map=${CYIME_JNI_DIR}=.")
set(Glog_FOUND TRUE CACHE BOOL "" FORCE)
set(Glog_INCLUDE_PATH "${CYIME_JNI_DIR}/librime/deps/glog/src" CACHE PATH "" FORCE)
set(Glog_LIBRARY glog CACHE STRING "" FORCE)
set(Glog_STATIC TRUE CACHE BOOL "" FORCE)

# yaml-cpp
option(YAML_CPP_BUILD_TOOLS "" OFF)
option(YAML_CPP_BUILD_TESTS "" OFF)
option(YAML_CPP_INSTALL "" OFF)
add_subdirectory("${CYIME_JNI_DIR}/librime/deps/yaml-cpp" "${CMAKE_BINARY_DIR}/librime/deps/yaml-cpp")
set(YamlCpp_FOUND TRUE CACHE BOOL "" FORCE)
set(YamlCpp_INCLUDE_PATH "${CYIME_JNI_DIR}/librime/deps/yaml-cpp/include" CACHE PATH "" FORCE)
set(YamlCpp_LIBRARY yaml-cpp CACHE STRING "" FORCE)
set(YamlCpp_STATIC TRUE CACHE BOOL "" FORCE)
set(YamlCpp_NEW_API TRUE CACHE BOOL "" FORCE)

# snappy
option(SNAPPY_BUILD_TESTS "" OFF)
option(SNAPPY_BUILD_BENCHMARKS "" OFF)
option(SNAPPY_INSTALL "" OFF)
add_subdirectory("${CYIME_JNI_DIR}/snappy" "${CMAKE_BINARY_DIR}/snappy")

# leveldb
set(HAVE_SNAPPY TRUE)
option(LEVELDB_BUILD_TESTS "" OFF)
option(LEVELDB_BUILD_BENCHMARKS "" OFF)
option(LEVELDB_INSTALL "" OFF)
add_subdirectory("${CYIME_JNI_DIR}/librime/deps/leveldb" "${CMAKE_BINARY_DIR}/librime/deps/leveldb")
set(LevelDb_FOUND TRUE CACHE BOOL "" FORCE)
set(LevelDb_INCLUDE_PATH "${CYIME_JNI_DIR}/librime/deps/leveldb/include" CACHE PATH "" FORCE)
set(LevelDb_LIBRARY leveldb CACHE STRING "" FORCE)
set(LevelDb_STATIC TRUE CACHE BOOL "" FORCE)

# marisa-trie
set(ENABLE_TOOLS OFF CACHE BOOL "" FORCE)
add_subdirectory("${CYIME_JNI_DIR}/librime/deps/marisa-trie" "${CMAKE_BINARY_DIR}/librime/deps/marisa-trie")
target_compile_options(marisa PRIVATE "-ffile-prefix-map=${CYIME_JNI_DIR}=.")
set(Marisa_FOUND TRUE CACHE BOOL "" FORCE)
set(Marisa_INCLUDE_PATH "${CYIME_JNI_DIR}/librime/deps/marisa-trie/include" CACHE PATH "" FORCE)
set(Marisa_LIBRARY marisa CACHE STRING "" FORCE)
set(Marisa_STATIC TRUE CACHE BOOL "" FORCE)
set(LIBMARISA marisa)
option(USE_SYSTEM_MARISA "" ON)

# opencc
add_subdirectory("${CYIME_JNI_DIR}/librime/deps/opencc" "${CMAKE_BINARY_DIR}/librime/deps/opencc")
include(OpenccWorkarounds)
set(Opencc_FOUND TRUE CACHE BOOL "" FORCE)
set(Opencc_INCLUDE_PATH "${CYIME_JNI_DIR}/librime/deps/opencc/src" CACHE PATH "" FORCE)
set(Opencc_LIBRARY libopencc CACHE STRING "" FORCE)
set(Opencc_STATIC TRUE CACHE BOOL "" FORCE)

# Boost 头文件 include 目录（与 Android 主 CMakeLists 相同）。
set(X11Keysym "${CYIME_JNI_DIR}/librime/include")
include_directories(
    "${X11Keysym}"
    "${CMAKE_BINARY_DIR}/include"
    "${CYIME_JNI_DIR}/boost/libs/algorithm/include"
    "${CYIME_JNI_DIR}/boost/libs/crc/include"
    "${CYIME_JNI_DIR}/boost/libs/dll/include"
    "${CYIME_JNI_DIR}/boost/libs/interprocess/include"
    "${CYIME_JNI_DIR}/boost/libs/range/include"
    "${CYIME_JNI_DIR}/boost/libs/regex/include"
    "${CYIME_JNI_DIR}/boost/libs/scope_exit/include"
    "${CYIME_JNI_DIR}/boost/libs/signals2/include"
    "${CYIME_JNI_DIR}/boost/libs/utility/include"
    "${CYIME_JNI_DIR}/boost/libs/uuid/include"
    "${CYIME_JNI_DIR}/boost/libs/assert/include"
    "${CYIME_JNI_DIR}/boost/libs/config/include"
    "${CYIME_JNI_DIR}/boost/libs/core/include"
    "${CYIME_JNI_DIR}/boost/libs/throw_exception/include"
    "${CYIME_JNI_DIR}/boost/libs/static_assert/include"
    "${CYIME_JNI_DIR}/boost/libs/mpl/include"
    "${CYIME_JNI_DIR}/boost/libs/preprocessor/include"
    "${CYIME_JNI_DIR}/boost/libs/vmd/include"
    "${CYIME_JNI_DIR}/boost/libs/type_traits/include"
    "${CYIME_JNI_DIR}/boost/libs/smart_ptr/include"
    "${CYIME_JNI_DIR}/boost/libs/move/include"
    "${CYIME_JNI_DIR}/boost/libs/container/include"
    "${CYIME_JNI_DIR}/boost/libs/container_hash/include"
    "${CYIME_JNI_DIR}/boost/libs/describe/include"
    "${CYIME_JNI_DIR}/boost/libs/intrusive/include"
    "${CYIME_JNI_DIR}/boost/libs/detail/include"
    "${CYIME_JNI_DIR}/boost/libs/integer/include"
    "${CYIME_JNI_DIR}/boost/libs/predef/include"
    "${CYIME_JNI_DIR}/boost/libs/io/include"
    "${CYIME_JNI_DIR}/boost/libs/lexical_cast/include"
    "${CYIME_JNI_DIR}/boost/libs/numeric/conversion/include"
    "${CYIME_JNI_DIR}/boost/libs/spirit/include"
    "${CYIME_JNI_DIR}/boost/libs/serialization/include"
    "${CYIME_JNI_DIR}/boost/libs/foreach/include"
    "${CYIME_JNI_DIR}/boost/libs/iterator/include"
    "${CYIME_JNI_DIR}/boost/libs/function/include"
    "${CYIME_JNI_DIR}/boost/libs/bind/include"
    "${CYIME_JNI_DIR}/boost/libs/tuple/include"
    "${CYIME_JNI_DIR}/boost/libs/optional/include"
    "${CYIME_JNI_DIR}/boost/libs/any/include"
    "${CYIME_JNI_DIR}/boost/libs/array/include"
    "${CYIME_JNI_DIR}/boost/libs/mp11/include"
    "${CYIME_JNI_DIR}/boost/libs/unordered/include"
    "${CYIME_JNI_DIR}/boost/libs/multi_index/include"
    "${CYIME_JNI_DIR}/boost/libs/variant/include"
    "${CYIME_JNI_DIR}/boost/libs/concept_check/include"
)

# ---- 打补丁 + 拷贝插件（复刻 Rime.cmake 的核心步骤） ----
include(CyimePatches)
cyime_apply_patch("${CYIME_JNI_DIR}/librime-octagram" "${CYIME_JNI_DIR}/cmake/OctagramT9.patch")

set(RIME_PLUGINS librime-octagram librime-predict librime-t9 cyime_azookey)
foreach(plugin ${RIME_PLUGINS})
  file(COPY "${CYIME_JNI_DIR}/${plugin}/"
       DESTINATION "${CYIME_JNI_DIR}/librime/plugins/${plugin}")
endforeach()
file(COPY "${CYIME_JNI_DIR}/librime-lua/"
     DESTINATION "${CYIME_JNI_DIR}/librime/plugins/lua")
if(NOT EXISTS "${CYIME_JNI_DIR}/librime/plugins/lua/thirdparty")
  file(COPY "${CYIME_JNI_DIR}/librime-lua-deps/"
       DESTINATION "${CYIME_JNI_DIR}/librime/plugins/lua/thirdparty")
endif()

# T9 整句重排依赖 onnxruntime（t9_sentence_scorer.cc 硬 include onnxruntime_cxx_api.h）。
# iOS 不引入 ONNX：删掉拷贝进 plugins 的这个文件，改用无 ONNX 桩；
# Android 发布包本就不打包模型，行为一致。
file(REMOVE "${CYIME_JNI_DIR}/librime/plugins/librime-t9/src/t9_sentence_scorer.cc")

cyime_apply_patch("${CYIME_JNI_DIR}/librime" "${CYIME_JNI_DIR}/cmake/RimeDictionary.patch")

# ---- 构建 librime ----
add_subdirectory("${CYIME_JNI_DIR}/librime" "${CMAKE_BINARY_DIR}/librime")
target_compile_options(
  rime-static PRIVATE "-ffile-prefix-map=${CYIME_JNI_DIR}=." "-Wno-error=deprecated-declarations")

# ---- 把 CyIME 自定义 C++ 编进 rime-static ----
target_include_directories(rime-static PRIVATE "${CYIME_JNI_DIR}/librime-t9/src")
target_include_directories(rime-static PRIVATE "${CYIME_JNI_DIR}/librime-octagram/src")
target_include_directories(rime-octagram-objs PRIVATE "${CYIME_JNI_DIR}/librime-t9/src")
target_include_directories(rime-static PRIVATE "${CYIME_JNI_DIR}/cyime_rime")
# cyime_rime/t9_cylm_sentence.h 会 include <cylm.h>，需要 cylm 目录。
target_include_directories(rime-static PRIVATE "${CYIME_JNI_DIR}/cylm")
target_sources(rime-static PRIVATE
  "${CYIME_JNI_DIR}/cyime_rime/t9_script_options.cc"
  "${CYIME_JNI_DIR}/cyime_rime/t9_cylm_sentence.cc"
  "${CYIME_JNI_DIR}/cyime_rime/t9_sentence_rescore.cc"
  "${CYIME_JNI_DIR}/cyime_rime/full_pinyin_tail.cc"
  "${CYIME_JNI_DIR}/cyime_rime/t9_joint_decoder.cc"
  # CyLM 解码器：编译，但不定义 CYLM_ORT（其重排器走内置的“无 ONNX”桩分支），
  # 这样既满足 cyime_rime 的链接需求，又不引入 onnxruntime。
  "${CYIME_JNI_DIR}/cylm/cylm.cpp"
  # 无 ONNX 的整句重排桩（替代被移除的 t9_sentence_scorer.cc）。
  "${CMAKE_CURRENT_LIST_DIR}/t9_sentence_scorer_stub.cc")

set_source_files_properties("${CYIME_JNI_DIR}/cylm/cylm.cpp"
  TARGET_DIRECTORY rime-static
  PROPERTIES
  COMPILE_DEFINITIONS "CYLM_LIBRARY"
  COMPILE_OPTIONS "-Wno-unused-result")

# ---- 输出：把 rime-static 及其依赖合并成一个静态库 ----
# 由 build-native.sh 用 libtool -static 合并，这里只保证 rime-static 目标存在。
