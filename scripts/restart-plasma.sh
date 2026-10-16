#!/usr/bin/env bash

set -u

plugin_id="${1:-io.github.xjimlinx.pianist}"
service="plasma-plasmashell.service"
watchdog_seconds="${PIANIST_WATCHDOG_SECONDS:-10}"
memory_limit_bytes=$((2 * 1024 * 1024 * 1024))
memory_growth_limit_bytes=$((512 * 1024 * 1024))
cpu_growth_limit_bytes=$((128 * 1024 * 1024))
failure_reason=""
failure_details=""
health_summary=""

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

service_main_pid() {
    systemctl --user show "$service" -p MainPID --value 2>/dev/null || true
}

service_memory() {
    systemctl --user show "$service" -p MemoryCurrent --value 2>/dev/null || true
}

process_cpu_ticks() {
    local pid="$1"
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] && [[ -r "/proc/$pid/stat" ]] || return 1
    awk '{ print $14 + $15 }' "/proc/$pid/stat"
}

fail_health_check() {
    failure_reason="$1"
    failure_details="${2:-}"
    return 1
}

observe_plasma() {
    local pid start_memory current_memory growth start_ticks end_ticks
    local clock_ticks cpu_percent attempt

    pid="$(service_main_pid)"
    start_memory="$(service_memory)"
    start_ticks="$(process_cpu_ticks "$pid" || true)"
    clock_ticks="$(getconf CLK_TCK 2>/dev/null || printf '100')"

    if [[ ! "$pid" =~ ^[1-9][0-9]*$ ]] || [[ ! -r "/proc/$pid/stat" ]]; then
        fail_health_check 'plasmashell 没有有效的主进程。' "MainPID=${pid:-missing}"
        return 1
    fi

    echo "正在观察 plasmashell ${watchdog_seconds} 秒，检测无响应、内存失控和持续高负载……"
    for attempt in $(seq 1 "$watchdog_seconds"); do
        sleep 1
        if [[ "$(service_state)" != "active" ]] || [[ "$(service_main_pid)" != "$pid" ]]; then
            fail_health_check 'plasmashell 在观察期内退出或被重新启动。' \
                "expected_pid=$pid current_pid=$(service_main_pid) state=$(service_state)"
            return 1
        fi

        if ! plasma_responds; then
            # Allow one transient busy second, but never accept a stuck QML event loop.
            if ! plasma_responds; then
                fail_health_check 'plasmashell 已失去 D-Bus 响应，疑似 QML 主线程死循环。' \
                    "pid=$pid check=${attempt}/${watchdog_seconds}"
                return 1
            fi
        fi

        current_memory="$(service_memory)"
        if [[ "$current_memory" =~ ^[0-9]+$ ]] && (( current_memory > memory_limit_bytes )); then
            fail_health_check 'plasmashell 内存超过 2 GiB 安全上限。' \
                "pid=$pid memory_mib=$((current_memory / 1024 / 1024))"
            return 1
        fi
        if [[ "$start_memory" =~ ^[0-9]+$ && "$current_memory" =~ ^[0-9]+$ ]]; then
            growth=$((current_memory - start_memory))
            if (( growth > memory_growth_limit_bytes )); then
                fail_health_check 'plasmashell 内存在观察期内增长超过 512 MiB。' \
                    "pid=$pid growth_mib=$((growth / 1024 / 1024))"
                return 1
            fi
        fi
    done

    current_memory="$(service_memory)"
    end_ticks="$(process_cpu_ticks "$pid" || true)"
    cpu_percent=0
    if [[ "$start_ticks" =~ ^[0-9]+([.][0-9]+)?$ \
          && "$end_ticks" =~ ^[0-9]+([.][0-9]+)?$ \
          && "$clock_ticks" =~ ^[1-9][0-9]*$ ]]; then
        cpu_percent=$(( (${end_ticks%.*} - ${start_ticks%.*}) * 100 \
                         / clock_ticks / watchdog_seconds ))
    fi
    growth=0
    if [[ "$start_memory" =~ ^[0-9]+$ && "$current_memory" =~ ^[0-9]+$ ]]; then
        growth=$((current_memory - start_memory))
    fi
    health_summary="pid=$pid memory_mib=$(( ${current_memory:-0} / 1024 / 1024 )) growth_mib=$((growth / 1024 / 1024)) cpu_percent=$cpu_percent"

    if (( cpu_percent >= 90 && growth > cpu_growth_limit_bytes )); then
        fail_health_check 'plasmashell 持续占满 CPU 且内存快速增长。' "$health_summary"
        return 1
    fi
    return 0
}

wait_for_healthy_plasma() {
    local attempt state active_failures
    active_failures=0
    for attempt in $(seq 1 100); do
        state="$(service_state)"
        if [[ "$state" == "active" ]]; then
            if plasma_responds; then
                observe_plasma
                return $?
            fi
            active_failures=$((active_failures + 1))
            if (( active_failures >= 3 )); then
                fail_health_check 'plasmashell 已启动，但连续三次没有 D-Bus 响应。' \
                    "state=$state pid=$(service_main_pid)"
                return 1
            fi
        fi
        sleep 0.1
    done
    fail_health_check 'plasmashell 未能在启动期限内进入可响应状态。' \
        "state=$(service_state) pid=$(service_main_pid)"
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

print_failure_report() {
    echo "错误：${failure_reason:-未知健康检查错误}"
    if [[ -n "$failure_details" ]]; then
        echo "诊断：$failure_details"
    fi
    echo '最近的 Plasma/QML 相关日志：'
    journalctl --user -u "$service" --since '-2 minutes' --no-pager -o short-precise 2>/dev/null \
        | grep -Ei "${plugin_id}|pianist|qml|binding loop|error|failed|memory|segfault|core" \
        | tail -80 || true
}

main() {
    local quarantined
    if [[ ! "$watchdog_seconds" =~ ^[1-9][0-9]*$ ]] || (( watchdog_seconds > 60 )); then
        echo 'PIANIST_WATCHDOG_SECONDS 必须是 1 到 60 之间的整数。'
        return 2
    fi

    if ! command -v systemctl >/dev/null 2>&1 \
       || ! systemctl --user cat "$service" >/dev/null 2>&1; then
        echo '无法通过 Plasma 用户服务安全重启；请注销后重新登录。'
        return 1
    fi

    echo '正在重启 plasmashell；桌面和面板会短暂消失后自动恢复……'
    stop_plasma || true
    if start_plasma; then
        echo "plasmashell 已恢复并通过运行时看门狗检查：$health_summary"
        return 0
    fi

    print_failure_report
    echo '新 plasmashell 未通过运行时看门狗检查，正在自动关闭并隔离 Pianist……'
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
    return 1
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
