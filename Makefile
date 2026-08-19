# flutter_netease_music / musiclibrary NDK build Makefile
# 用法: make help
# 原则: 系统里有什么用什么,不单独装 NDK (只用 SDK 已有的 29.0.14206865)

NDK_VERSION   := 29.0.14206865
PROJECT_ROOT  := $(shell pwd)
ANDROID_DIR   := $(PROJECT_ROOT)/android
MUSICLIB_DIR  := $(PROJECT_ROOT)/packages/musiclibrary/android

NDK_PATH := $(ANDROID_HOME)/ndk/$(NDK_VERSION)
ifeq ($(wildcard $(NDK_PATH)),)
NDK_PATH := $(ANDROID_SDK_ROOT)/ndk/$(NDK_VERSION)
endif
ifeq ($(wildcard $(NDK_PATH)),)
NDK_PATH := ~/Android/Sdk/ndk/$(NDK_VERSION)
endif
ifeq ($(wildcard $(NDK_PATH)),)
NDK_PATH := /opt/android-sdk/ndk/$(NDK_VERSION)
endif

.PHONY: help env check clean distclean build build-app build-plugin build-native-only log

help: ## 显示帮助
	@echo "用法:"
	@echo "  make env              检查 NDK / Flutter / Java 环境"
	@echo "  make build            全量构建 :app:assembleDebug (含 plugin)"
	@echo "  make build-app        只构建 app 模块 (依赖 plugin 已 build 过)"
	@echo "  make build-plugin     只构建 musiclibrary plugin (含 NDK CMake)"
	@echo "  make build-native-only 只跑 native (CMake) 构建,不出 APK"
	@echo "  make clean            清理 app build/"
	@echo "  make distclean        清理 app + plugin + cxx cache"
	@echo "  make log              跑 build 并把日志写到 ./build.log"

env: ## 检查环境
	@echo "NDK path = $(NDK_PATH)"
	@if [ ! -d "$(NDK_PATH)" ]; then \
		echo "❌ NDK $(NDK_VERSION) 不存在!"; \
		echo "   系统里装的是:"; \
		ls /opt/android-sdk/ndk/ 2>/dev/null || ls ~/Android/Sdk/ndk/ 2>/dev/null || echo "  (找不到 SDK)"; \
		exit 1; \
	fi
	@echo "✓ NDK OK"
	@which flutter && flutter --version | head -1 || echo "❌ flutter 不在 PATH"
	@which java && java -version 2>&1 | head -1 || echo "❌ java 不在 PATH"
	@echo "ANDROID_HOME   = $(ANDROID_HOME)"
	@echo "ANDROID_SDK_ROOT = $(ANDROID_SDK_ROOT)"

check: env

build: ## 全量构建 :app:assembleDebug (默认目标)
	cd $(ANDROID_DIR) && ./gradlew :app:assembleDebug

build-app: ## 只构建 app 模块
	cd $(ANDROID_DIR) && ./gradlew :app:assembleDebug

build-plugin: ## 只构建 musiclibrary plugin
	cd $(ANDROID_DIR) && ./gradlew :musiclibrary:assembleDebug

build-native-only: ## 只跑 native (CMake) 构建,跳过 APK 打包
	cd $(ANDROID_DIR) && ./gradlew :musiclibrary:externalNativeBuildDebug

clean: ## 清理 app build/
	cd $(ANDROID_DIR) && ./gradlew clean

distclean: ## 清理 app + plugin + cxx cache
	cd $(ANDROID_DIR) && ./gradlew clean
	rm -rf $(ANDROID_DIR)/app/build
	rm -rf $(MUSICLIB_DIR)/build
	rm -rf $(ANDROID_DIR)/.cxx
	rm -rf $(PROJECT_ROOT)/build

log: ## 跑 build 并把日志写到 ./build.log
	cd $(ANDROID_DIR) && ./gradlew :app:assembleDebug 2>&1 | tee $(PROJECT_ROOT)/build.log

.DEFAULT_GOAL := help