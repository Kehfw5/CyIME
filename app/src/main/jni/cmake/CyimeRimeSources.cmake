# CyIME code compiled into rime-static: the decoder sources in cyime_rime/ and the CyLM decoder.
# Rime calls them from explicit hooks in RimeDictionary.patch / patches/cyime-librime.patch.
file(READ "${CYIME_ROOT}/librime/src/rime/gear/script_translator.cc" CYIME_SCRIPT_TRANSLATOR)
string(FIND "${CYIME_SCRIPT_TRANSLATOR}" "T9DecodeJoint(" CYIME_DECODER_HOOK)
if(CYIME_DECODER_HOOK EQUAL -1)
  message(FATAL_ERROR "CyIME decoder hooks missing from librime; the librime patch was not applied")
endif()
target_include_directories(rime-static PRIVATE "${CYIME_ROOT}/librime-t9/src")
target_include_directories(rime-static PRIVATE "${CYIME_ROOT}/librime-octagram/src")
# OctagramT9.patch includes t9_lookup_trace.h (work counters, empty outside the host replay).
target_include_directories(rime-octagram-objs PRIVATE "${CYIME_ROOT}/librime-t9/src")
# CyLM decoder (cylm/cylm.cpp, also built alone as libcylm.so): used only when a schema names its files.
target_include_directories(rime-static PRIVATE "${CYIME_ROOT}/cylm")
target_sources(rime-static PRIVATE "${CYIME_ROOT}/cylm/cylm.cpp")
target_include_directories(rime-static PRIVATE "${CYIME_ROOT}/cyime_rime")
target_sources(rime-static PRIVATE "${CYIME_ROOT}/cyime_rime/t9_script_options.cc"
               "${CYIME_ROOT}/cyime_rime/t9_cylm_sentence.cc"
               "${CYIME_ROOT}/cyime_rime/t9_sentence_rescore.cc"
               "${CYIME_ROOT}/cyime_rime/full_pinyin_tail.cc"
               "${CYIME_ROOT}/cyime_rime/t9_joint_decoder.cc")
# Source properties are per directory: set it where rime-static is defined, or main() gets linked in.
set_source_files_properties("${CYIME_ROOT}/cylm/cylm.cpp" TARGET_DIRECTORY rime-static PROPERTIES COMPILE_DEFINITIONS "CYLM_LIBRARY;CYLM_ORT"
  # OrtStatus results of option setters are ignored on purpose in cylm.cpp; the NDK build treats that as an error.
  COMPILE_OPTIONS "-Wno-unused-result")
# The reranker uses the onnxruntime C API; rime-static links onnxruntime already (jni CMakeLists).
target_include_directories(rime-static PRIVATE "${CYIME_ROOT}/onnxruntime/include")
