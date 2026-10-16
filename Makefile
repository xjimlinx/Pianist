SHELL := /bin/bash

PLUGIN_ID := io.github.xjimlinx.pianist
PACKAGE_TYPE := Plasma/Applet
PACKAGE_DIR := $(CURDIR)/package

KPACKAGETOOL ?= kpackagetool6
PLASMAWINDOWED ?= plasmawindowed
QMLLINT ?= qmllint
QMLTESTRUNNER ?= /usr/lib/qt6/bin/qmltestrunner
NODE ?= node

.DEFAULT_GOAL := help

.PHONY: help install update upgrade deploy reload restart uninstall preview test test-qml test-qml-runtime test-js test-shell

help:
	@printf '%s\n' \
		'Pianist Plasma 开发命令：' \
		'  make install   首次安装；已安装时自动升级' \
		'  make update    更新已安装的插件（install 的别名）' \
		'  make reload    重启 plasmashell，重新加载插件 QML' \
		'  make restart   与 reload 相同（保留兼容）' \
		'  make deploy    安装/更新并重启 plasmashell' \
		'  make preview   更新后用 plasmawindowed 调试预览' \
		'  make test      运行 QML、JavaScript 与脚本检查' \
		'  make uninstall 卸载 Plasmoid（不会主动删除 KDE 配置）'

install:
	@command -v "$(KPACKAGETOOL)" >/dev/null || { echo '缺少 kpackagetool6，请先安装 KDE Plasma 6 开发工具。'; exit 1; }
	@if "$(KPACKAGETOOL)" --type "$(PACKAGE_TYPE)" --show "$(PLUGIN_ID)" >/dev/null 2>&1; then \
		echo 'Pianist 已安装，正在升级插件文件……'; \
		"$(KPACKAGETOOL)" --type "$(PACKAGE_TYPE)" --upgrade "$(PACKAGE_DIR)"; \
	else \
		echo '正在首次安装 Pianist……'; \
		"$(KPACKAGETOOL)" --type "$(PACKAGE_TYPE)" --install "$(PACKAGE_DIR)"; \
	fi

update upgrade: install

reload:
	@./scripts/restart-plasma.sh "$(PLUGIN_ID)"

restart: reload

deploy:
	@$(MAKE) --no-print-directory install
	@$(MAKE) --no-print-directory restart

uninstall:
	@command -v "$(KPACKAGETOOL)" >/dev/null || { echo '缺少 kpackagetool6。'; exit 1; }
	@if "$(KPACKAGETOOL)" --type "$(PACKAGE_TYPE)" --show "$(PLUGIN_ID)" >/dev/null 2>&1; then \
		"$(KPACKAGETOOL)" --type "$(PACKAGE_TYPE)" --remove "$(PLUGIN_ID)"; \
	else \
		echo 'Pianist 当前未安装。'; \
	fi

preview:
	@$(MAKE) --no-print-directory install
	@command -v "$(PLASMAWINDOWED)" >/dev/null || { echo '缺少 plasmawindowed。'; exit 1; }
	@"$(PLASMAWINDOWED)" -p org.kde.plasma.desktop "$(PLUGIN_ID)"

test: test-qml test-qml-runtime test-js test-shell

test-qml:
	@command -v "$(QMLLINT)" >/dev/null || { echo '缺少 qmllint。'; exit 1; }
	@"$(QMLLINT)" \
		package/contents/code/Store.js \
		package/contents/ui/main.qml \
		package/contents/ui/GoalTree.qml \
		package/contents/ui/configAppearance.qml \
		tests/tst_goal_tree.qml \
		tests/tst_shared_settings.qml

test-qml-runtime:
	@command -v "$(QMLTESTRUNNER)" >/dev/null || { echo '缺少 qmltestrunner。'; exit 1; }
	@QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
		"$(QMLTESTRUNNER)" -input tests/tst_goal_tree.qml
	@QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
		"$(QMLTESTRUNNER)" -input tests/tst_shared_settings.qml

test-js:
	@command -v "$(NODE)" >/dev/null || { echo '缺少 Node.js。'; exit 1; }
	@"$(NODE)" tests/store.test.js

test-shell:
	@bash -n scripts/restart-plasma.sh tests/restart-plasma.test.sh
	@bash tests/restart-plasma.test.sh
