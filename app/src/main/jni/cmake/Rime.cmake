# SPDX-FileCopyrightText: 2015 - 2024 Rime community
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Lua's Android fseeko guard comes from patches/cyime-lua-android.patch (Gradle applyCyimeSourcePatches).
include("${CMAKE_CURRENT_LIST_DIR}/CyimePatches.cmake")
# Nine-key whole-word grammar scoring and host replay counters; the plugin copy below picks it up.
cyime_apply_patch("${CYIME_ROOT}/librime-octagram" "${CMAKE_CURRENT_LIST_DIR}/OctagramT9.patch")

set(RIME_PLUGINS librime-octagram librime-predict librime-t9 cyime_azookey)

foreach(plugin ${RIME_PLUGINS})
  file(COPY "${CYIME_ROOT}/${plugin}/"
       DESTINATION "${CYIME_ROOT}/librime/plugins/${plugin}")
endforeach()

file(COPY "${CYIME_ROOT}/librime-lua/"
     DESTINATION "${CYIME_ROOT}/librime/plugins/lua")

if(NOT EXISTS "${CYIME_ROOT}/librime/plugins/lua/thirdparty")
  file(COPY "${CYIME_ROOT}/librime-lua-deps/"
       DESTINATION "${CYIME_ROOT}/librime/plugins/lua/thirdparty")
endif()

option(BUILD_TEST "" OFF)
option(BUILD_STATIC "" ON)
option(CYIME_RIME_VERBOSE_TRACE "Trace every native dictionary lookup (slow)" OFF)
if(CYIME_RIME_VERBOSE_TRACE)
  add_compile_definitions(CYIME_RIME_VERBOSE_TRACE=1)
endif()
include("${CMAKE_CURRENT_LIST_DIR}/T9WorkCounters.cmake")
# Every CyIME change to librime; the same file as patches/cyime-librime.patch, which Gradle applies first.
cyime_apply_patch("${CYIME_ROOT}/librime" "${CMAKE_CURRENT_LIST_DIR}/RimeDictionary.patch")
add_subdirectory(librime)
include("${CMAKE_CURRENT_LIST_DIR}/CyimeRimeSources.cmake")
target_compile_options(
  rime-static PRIVATE "-ffile-prefix-map=${CYIME_ROOT}=." "-Wno-error=deprecated-declarations")

target_compile_options(
  rime-lua-objs PRIVATE "-ffile-prefix-map=${CYIME_ROOT}=.")
