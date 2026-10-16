#!/usr/bin/env bash

set -u

plugin_id="${1:-io.github.baozixu99.litelist}"
service="plasma-plasmashell.service"

service_state() {
    systemctl --user is-active "$service" 2>/dev/null || true
}

stop_plasma() {
    systemctl --user stop --no-block "$service" >/dev/null 2>&1 || true

    local attempt state
    for attempt in $(seq 1 30); do
        state="$(service_state)"
        if [[ "$state" == "inactive" || "$state" == "failed" || "$state" == "unknown" ]]; then
            return 0
        fi
        sleep 0.1
    done

    echo '旧 plasmashell 未在 3 秒内退出，正在强制结束旧进程……'
    systemctl --user kill --signal=SIGKILL --kill-whom=main "$service" >/dev/null 2>&1 || true
    for attempt in $(seq 1 50); do
        state="$(service_state)"
        if [[ "$state" != "deactivating" ]]; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

plasma_responds() {
    command -v qdbus6 >/dev/null 2>&1 || return 0
    timeout 1s qdbus6 org.kde.plasmashell /PlasmaShell \
        org.freedesktop.DBus.Peer.Ping >/dev/null 2>&1
}

wait_for_healthy_plasma() {
    local attempt state memory
    for attempt in $(seq 1 100); do
        state="$(service_state)"
        if [[ "$state" == "active" ]] && plasma_responds; then
            # A Type=dbus service becomes active as soon as it owns its name.
            # Give QML/applets time to load, then require a second response.
            sleep 3
            if ! plasma_responds; then
                return 1
            fi
            memory="$(systemctl --user show "$service" -p MemoryCurrent --value 2>/dev/null || true)"
            if [[ "$memory" =~ ^[0-9]+$ ]] && (( memory > 2147483648 )); then
                return 1
            fi
            return 0
        fi
        sleep 0.1
    done
    return 1
}

start_plasma() {
    systemctl --user reset-failed "$service" >/dev/null 2>&1 || true
    systemctl --user start --no-block "$service" >/dev/null 2>&1 || return 1
    wait_for_healthy_plasma
}

plugin_directory() {
    local data_home account_home
    data_home="${XDG_DATA_HOME:-}"
    if [[ "$data_home" != /* ]]; then
        account_home="$(getent passwd "$(id -u)" | cut -d: -f6)"
        data_home="$account_home/.local/share"
    fi
    printf '%s/plasma/plasmoids/%s\n' "$data_home" "$plugin_id"
}

quarantine_plugin() {
    local source target timestamp
    source="$(plugin_directory)"
    [[ -d "$source" ]] || return 1
    timestamp="$(date +%Y%m%d-%H%M%S)"
    target="${source}.failed-${timestamp}"
    mv -- "$source" "$target" || return 1
    printf '%s\n' "$target"
}

if ! command -v systemctl >/dev/null 2>&1 \
   || ! systemctl --user cat "$service" >/dev/null 2>&1; then
    echo '无法通过 Plasma 用户服务安全重启；请注销后重新登录。'
    exit 1
fi

echo '正在重启 plasmashell；桌面和面板会短暂消失后自动恢复……'
stop_plasma || true
if start_plasma; then
    echo 'plasmashell 已恢复运行并通过 D-Bus 健康检查。'
    exit 0
fi

echo '新 plasmashell 未通过健康检查，正在隔离 Pianist 并恢复桌面……'
stop_plasma || true
quarantined="$(quarantine_plugin || true)"
if start_plasma; then
    if [[ -n "$quarantined" ]]; then
        echo "桌面已恢复；故障插件保留在：$quarantined"
    else
        echo '桌面已恢复，但没有找到可隔离的 Pianist 安装目录。'
    fi
else
    echo '隔离插件后 plasmashell 仍未恢复，请注销后重新登录。'
fi
exit 1
