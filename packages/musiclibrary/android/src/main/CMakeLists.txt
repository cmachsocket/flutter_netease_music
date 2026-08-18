# musiclibrary Android 端 native build
#
# 只 build ncm_music_api 这一个共享库,其他(engine/kugou_music_api)用 option 关掉。
# libcurl 通过 AGP prefab 从 Maven 依赖里引入(NDK r29 不自带 libcurl)。
#
# 路径关系(plugin android 端在 packages/musiclibrary/android/src/main/):
#   MusicLibrary 主项目: ../../../../../MusicLibrary
#   其中 quickjs submodule: ../../../../../MusicLibrary/quickjs
cmake_minimum_required(VERSION 3.21)
project(musiclibrary_android LANGUAGES C)

# ========== 定位 MusicLibrary ==========
# CMAKE_CURRENT_SOURCE_DIR = packages/musiclibrary/android/src/main
# 上溯 5 级到 flutter_netease_music 根
get_filename_component(MUSICLIBRARY_ROOT
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../MusicLibrary"
    ABSOLUTE)

if(NOT EXISTS "${MUSICLIBRARY_ROOT}/CMakeLists.txt")
    message(FATAL_ERROR
        "MusicLibrary/CMakeLists.txt not found at ${MUSICLIBRARY_ROOT}.\n"
        "Make sure MusicLibrary git submodule is initialized:\n"
        "  git submodule update --init --recursive")
endif()

message(STATUS "musiclibrary: using MusicLibrary at ${MUSICLIBRARY_ROOT}")

# ========== libcurl via Prefab ==========
# AGP 8.0+ 默认开启 prefab。Google 官方包 com.android.ndk.thirdparty:curl 在
# plugin 的 build.gradle.kts 通过 implementation 引入,AGP 会生成 .cxx/.../prefab/modules/curl
# 并通过 -DCMAKE_FIND_ROOT_PATH 注入。find_package 要用小写 "curl" (AAR 内的 module 名)。
find_package(curl REQUIRED CONFIG)
message(STATUS "musiclibrary: libcurl found at ${curl_LIBRARIES}")

# ========== 子库选择 ==========
# Android 端只需要 ncm_music_api,关闭 engine / kugou 减少 APK 体积
# (engine 会被 ncm_music_api 间接依赖,所以这里仍然保留 ON;
#  kugou 完全不需要,关掉)
set(MUSICLIBRARY_BUILD_ENGINE ON CACHE BOOL "" FORCE)
set(MUSICLIBRARY_BUILD_KUGOU  OFF CACHE BOOL "" FORCE)
set(MUSICLIBRARY_BUILD_NCM    ON  CACHE BOOL "" FORCE)

# ========== 引入 MusicLibrary 主 CMakeLists ==========
add_subdirectory(${MUSICLIBRARY_ROOT}
                 ${CMAKE_CURRENT_BINARY_DIR}/musiclibrary_build)

# ========== link libcurl 给 engine_config (Android 平台需要) ==========
# MusicLibrary 主 CMakeLists 里只在 UNIX AND NOT ANDROID / WIN32 链接 curl,
# 所以 Android 平台默认 curl 是断的。这里手动补上。
# prefab 模块导出的是 "curl::curl" target,会自动传递依赖 (openssl)。
target_link_libraries(engine_config INTERFACE curl::curl)
target_link_libraries(engine           PRIVATE curl::curl)

# ========== 输出 ncm_music_api.so 给 Flutter 工具链打包 ==========
# 设置统一的输出目录,跟其他 plugin 的 native lib 输出保持一致
set_target_properties(ncm_music_api PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/output)

# 暴露给 flutter 工具链:声明 plugin bundle 了哪些 native lib
set(musiclibrary_bundled_libraries
    $<TARGET_FILE:ncm_music_api>
    PARENT_SCOPE)

# Android 15+ 需要 16KB page size 对齐
if(ANDROID)
    target_link_options(ncm_music_api PRIVATE "-Wl,-z,max-page-size=16384")
endif()
