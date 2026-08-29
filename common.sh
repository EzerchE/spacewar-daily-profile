#!/system/bin/sh

MODDIR="${0%/*}"
[ -f "$MODDIR/module.prop" ] || MODDIR=/data/adb/modules/spacewar-daily-profile

LOG="$MODDIR/module.log"
DIAGNOSTICS="$MODDIR/diagnostics.txt"
STOPFILE="$MODDIR/STOP"
MIGRATION_DONE="$MODDIR/.v101-retired-settings-restored"
LPM_RETIRE_DONE="$MODDIR/.v102-lpm-restored"
INPUT_BASELINE_V104="$MODDIR/.v104-input-baseline"
INPUT_RETIRE_DONE="$MODDIR/.v109-input-boost-retired"

LPM_TARGET=/sys/module/lpm_levels/parameters/sleep_disabled
ZRAM_DEV=/dev/block/zram0
ZRAM_SYS=/sys/block/zram0
INPUT_BOOST_FREQ=/sys/devices/system/cpu/cpu_boost/input_boost_freq
INPUT_BOOST_MS=/sys/devices/system/cpu/cpu_boost/input_boost_ms
SCHED_BOOST_INPUT=/sys/devices/system/cpu/cpu_boost/sched_boost_on_input
ORIGINAL_LPM="$MODDIR/original_sleep_disabled"
ORIGINAL_MOBILE_DATA="$MODDIR/original_mobile_data_always_on"
ORIGINAL_INPUT_BOOST_FREQ="$MODDIR/original_input_boost_freq"
ORIGINAL_INPUT_BOOST_MS="$MODDIR/original_input_boost_ms"
ORIGINAL_SCHED_BOOST_INPUT="$MODDIR/original_sched_boost_on_input"
LEGACY_DOZE_BASELINE="$MODDIR/original_device_idle_constants"
LEGACY_BT_BASELINE="$MODDIR/original_bluetooth_scan_timeout"
ABSENT=__ABSENT__

log_message() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"
}

read_one_line() {
    [ -r "$1" ] || return 1
    tr -d '\r\n' < "$1" 2>/dev/null
}

valid_lpm_value() {
    case "$1" in Y|y|N|n|0|1) return 0 ;; esac
    return 1
}

valid_binary_value() {
    case "$1" in 0|1) return 0 ;; esac
    return 1
}

valid_scan_timeout() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) [ "$1" -ge 60000 ] && [ "$1" -le 600000 ] ;;
    esac
}

import_file_if_valid() {
    source_file="$1"
    destination_file="$2"
    validator="$3"

    [ -s "$destination_file" ] && return 0
    [ -s "$source_file" ] || return 1
    value=$(read_one_line "$source_file")
    "$validator" "$value" || return 1
    printf '%s\n' "$value" > "$destination_file"
    log_message "Imported baseline $(basename "$destination_file")=$value from $source_file"
}

save_baselines() {
    import_file_if_valid /data/adb/modules/spacewar-lpm-restore/original_mobile_data_always_on "$ORIGINAL_MOBILE_DATA" valid_binary_value
    if [ ! -s "$ORIGINAL_MOBILE_DATA" ]; then
        value=$(settings get global mobile_data_always_on 2>/dev/null | tr -d '\r\n')
        valid_binary_value "$value" && printf '%s\n' "$value" > "$ORIGINAL_MOBILE_DATA"
    fi

    if [ ! -s "$ORIGINAL_INPUT_BOOST_FREQ" ] && [ -r "$INPUT_BOOST_FREQ" ]; then
        read_one_line "$INPUT_BOOST_FREQ" > "$ORIGINAL_INPUT_BOOST_FREQ"
    fi
    if [ ! -s "$ORIGINAL_INPUT_BOOST_MS" ] && [ -r "$INPUT_BOOST_MS" ]; then
        read_one_line "$INPUT_BOOST_MS" > "$ORIGINAL_INPUT_BOOST_MS"
    fi
    if [ ! -s "$ORIGINAL_SCHED_BOOST_INPUT" ] && [ -r "$SCHED_BOOST_INPUT" ]; then
        read_one_line "$SCHED_BOOST_INPUT" > "$ORIGINAL_SCHED_BOOST_INPUT"
    fi
}

migrate_retired_lpm() {
    [ -e "$LPM_RETIRE_DONE" ] && return 0

    original=$(read_one_line "$ORIGINAL_LPM")
    if valid_lpm_value "$original" && [ -w "$LPM_TARGET" ]; then
        printf '%s\n' "$original" > "$LPM_TARGET" 2>/dev/null
        log_message "Retired Qualcomm LPM override after suspend/UFS watchdog failure; restored ROM baseline=$original."
    else
        log_message "No valid saved Qualcomm LPM baseline found; kernel value left unchanged."
    fi

    touch "$LPM_RETIRE_DONE"
}

migrate_retired_settings() {
    [ -e "$MIGRATION_DONE" ] && return 0

    original=$(read_one_line "$LEGACY_DOZE_BASELINE")
    if [ "$original" = "$ABSENT" ]; then
        settings delete global device_idle_constants >/dev/null 2>&1
        log_message "Retired custom Doze timings; restored baseline=absent."
    elif [ -n "$original" ]; then
        settings put global device_idle_constants "$original" >/dev/null 2>&1
        log_message "Retired custom Doze timings; restored saved baseline."
    else
        log_message "No saved Doze baseline found; setting left unchanged."
    fi

    original=$(read_one_line "$LEGACY_BT_BASELINE")
    if [ "$original" = "$ABSENT" ]; then
        device_config delete bluetooth scan_timeout_millis >/dev/null 2>&1
        log_message "Retired Bluetooth scan timeout; restored baseline=absent."
    elif valid_scan_timeout "$original"; then
        device_config put bluetooth scan_timeout_millis "$original" >/dev/null 2>&1
        log_message "Retired Bluetooth scan timeout; restored baseline=${original}ms."
    else
        log_message "No valid Bluetooth scan-timeout baseline found; setting left unchanged."
    fi

    touch "$MIGRATION_DONE"
}

apply_static_profile() {
    current=$(settings get global mobile_data_always_on 2>/dev/null | tr -d '\r\n')
    if [ "$current" = 1 ]; then
        settings put global mobile_data_always_on 0 2>/dev/null
        log_message "Radio idle enabled: mobile_data_always_on 1 -> $(settings get global mobile_data_always_on 2>/dev/null)"
    elif [ "$current" != 0 ]; then
        log_message "WARNING: unknown mobile_data_always_on value '$current'; unchanged."
    fi
}

active_zram_algorithm() {
    [ -r "$ZRAM_SYS/comp_algorithm" ] || return 1
    awk '{
        for (i = 1; i <= NF; i++) {
            if ($i ~ /^\[/) {
                gsub(/^\[|\]$/, "", $i)
                print $i
                exit
            }
        }
    }' "$ZRAM_SYS/comp_algorithm"
}

print_zram_health() {
    [ -r "$ZRAM_SYS/mm_stat" ] || {
        printf 'zram_health=unavailable\n'
        return 0
    }

    set -- $(read_one_line "$ZRAM_SYS/mm_stat")
    orig_bytes=${1:-0}
    compressed_bytes=${2:-0}
    memory_bytes=${3:-0}
    memory_limit_bytes=${4:-0}
    memory_peak_bytes=${5:-0}
    same_pages=${6:-0}
    compacted_pages=${7:-0}
    huge_pages=${8:-0}

    set -- $(read_one_line "$ZRAM_SYS/io_stat")
    failed_reads=${1:-0}
    failed_writes=${2:-0}
    invalid_io=${3:-0}
    notify_free=${4:-0}

    swap_total_kb=$(awk '/^SwapTotal:/{print $2}' /proc/meminfo 2>/dev/null)
    swap_free_kb=$(awk '/^SwapFree:/{print $2}' /proc/meminfo 2>/dev/null)
    swap_total_kb=${swap_total_kb:-0}
    swap_free_kb=${swap_free_kb:-0}

    compression_ratio=$(awk -v o="$orig_bytes" -v c="$compressed_bytes" \
        'BEGIN { if (c > 0) printf "%.2f", o / c; else print "0.00" }')
    effective_ratio=$(awk -v o="$orig_bytes" -v m="$memory_bytes" \
        'BEGIN { if (m > 0) printf "%.2f", o / m; else print "0.00" }')
    saved_mib=$(awk -v o="$orig_bytes" -v m="$memory_bytes" \
        'BEGIN { if (o > m) printf "%.1f", (o - m) / 1048576; else print "0.0" }')
    swap_used_percent=$(awk -v t="$swap_total_kb" -v f="$swap_free_kb" \
        'BEGIN { if (t > 0) printf "%.1f", ((t - f) * 100) / t; else print "0.0" }')
    huge_percent=$(awk -v h="$huge_pages" -v o="$orig_bytes" \
        'BEGIN { if (o > 0) printf "%.1f", (h * 4096 * 100) / o; else print "0.0" }')
    psi_some_avg10=$(awk '/^some /{sub(/^avg10=/, "", $2); print $2}' /proc/pressure/memory 2>/dev/null)
    psi_some_avg60=$(awk '/^some /{sub(/^avg60=/, "", $3); print $3}' /proc/pressure/memory 2>/dev/null)
    psi_some_avg300=$(awk '/^some /{sub(/^avg300=/, "", $4); print $4}' /proc/pressure/memory 2>/dev/null)
    psi_full_avg10=$(awk '/^full /{sub(/^avg10=/, "", $2); print $2}' /proc/pressure/memory 2>/dev/null)
    psi_full_avg60=$(awk '/^full /{sub(/^avg60=/, "", $3); print $3}' /proc/pressure/memory 2>/dev/null)
    psi_full_avg300=$(awk '/^full /{sub(/^avg300=/, "", $4); print $4}' /proc/pressure/memory 2>/dev/null)

    health=healthy
    [ "$(active_zram_algorithm)" = lz4 ] || health=review_algorithm
    [ "$failed_reads" = 0 ] && [ "$failed_writes" = 0 ] && [ "$invalid_io" = 0 ] ||
        health=review_io
    awk -v p="$swap_used_percent" 'BEGIN { exit !(p >= 80) }' && health=review_capacity
    # Ignore short boot/application-launch bursts. Flag only sustained full
    # memory stalls averaging at least 1% across the five-minute PSI window.
    awk -v p="${psi_full_avg300:-0}" 'BEGIN { exit !(p >= 1.00) }' && health=review_pressure

    printf 'zram_health=%s\n' "$health"
    printf 'zram_compression_ratio=%s\n' "$compression_ratio"
    printf 'zram_effective_ratio=%s\n' "$effective_ratio"
    printf 'zram_saved_mib=%s\n' "$saved_mib"
    printf 'zram_swap_used_percent=%s\n' "$swap_used_percent"
    printf 'zram_incompressible_percent=%s\n' "$huge_percent"
    printf 'zram_memory_current_bytes=%s\n' "$memory_bytes"
    printf 'zram_memory_peak_bytes=%s\n' "$memory_peak_bytes"
    printf 'zram_memory_limit_bytes=%s\n' "$memory_limit_bytes"
    printf 'zram_same_pages=%s\n' "$same_pages"
    printf 'zram_compacted_pages=%s\n' "$compacted_pages"
    printf 'zram_io_errors=%s/%s/%s\n' "$failed_reads" "$failed_writes" "$invalid_io"
    printf 'zram_notify_free=%s\n' "$notify_free"
    printf 'memory_psi_some=%s/%s/%s (avg10/avg60/avg300)\n' \
        "${psi_some_avg10:-0}" "${psi_some_avg60:-0}" "${psi_some_avg300:-0}"
    printf 'memory_psi_full=%s/%s/%s (avg10/avg60/avg300)\n' \
        "${psi_full_avg10:-0}" "${psi_full_avg60:-0}" "${psi_full_avg300:-0}"
}

set_input_boost_pair() {
    [ -w "$INPUT_BOOST_FREQ" ] || return 1
    printf '%s\n' "$1" > "$INPUT_BOOST_FREQ" 2>/dev/null
}

restore_interaction_profile() {
    if [ -s "$ORIGINAL_INPUT_BOOST_FREQ" ] && [ -w "$INPUT_BOOST_FREQ" ]; then
        for pair in $(read_one_line "$ORIGINAL_INPUT_BOOST_FREQ"); do
            case "$pair" in
                [0-7]:[0-9]*) set_input_boost_pair "$pair" ;;
            esac
        done
    fi

    value=$(read_one_line "$ORIGINAL_INPUT_BOOST_MS")
    case "$value" in ''|*[!0-9]*) ;; *) printf '%s\n' "$value" > "$INPUT_BOOST_MS" 2>/dev/null ;; esac
    value=$(read_one_line "$ORIGINAL_SCHED_BOOST_INPUT")
    case "$value" in 0|1|2) printf '%s\n' "$value" > "$SCHED_BOOST_INPUT" 2>/dev/null ;; esac
    log_message "Restored saved legacy input-boost baseline."
}

retire_interaction_profile() {
    [ -e "$INPUT_RETIRE_DONE" ] && return 0

    if [ -e "$INPUT_BOOST_FREQ" ]; then
        restore_interaction_profile
        log_message "Retired legacy cpu_boost tuning; restored the saved ROM baseline."
    else
        log_message "Retired legacy cpu_boost tuning; Willays kernel exposes no legacy cpu_boost interface."
    fi

    touch "$INPUT_RETIRE_DONE"
}

restore_all() {
    original=$(read_one_line "$ORIGINAL_MOBILE_DATA")
    if valid_binary_value "$original"; then
        settings put global mobile_data_always_on "$original" 2>/dev/null
        log_message "Restored mobile_data_always_on baseline=$original"
    fi
    restore_interaction_profile
}

print_status() {
    printf 'module=spacewar-daily-profile\n'
    printf 'version=1.0.9\n'
    printf 'sleep_disabled=%s (managed=no retired_baseline=%s)\n' "$(read_one_line "$LPM_TARGET")" "$(read_one_line "$ORIGINAL_LPM")"
    printf 'mobile_data_always_on=%s (managed=0 original=%s)\n' "$(settings get global mobile_data_always_on 2>/dev/null)" "$(read_one_line "$ORIGINAL_MOBILE_DATA")"
    printf 'zram_algorithm=%s (managed=pre-init-lz4-only)\n' "$(active_zram_algorithm)"
    printf 'zram_size=%s\n' "$(read_one_line "$ZRAM_SYS/disksize")"
    print_zram_health
    if [ -r "$INPUT_BOOST_FREQ" ]; then
        printf 'legacy_input_boost=%s (managed=no)\n' "$(read_one_line "$INPUT_BOOST_FREQ")"
    else
        printf 'legacy_input_boost=unavailable (managed=no; Android Power HAL authoritative)\n'
    fi
    printf 'device_idle_constants=%s (managed=no)\n' "$(settings get global device_idle_constants 2>/dev/null)"
    printf 'bluetooth_scan_timeout_ms=%s (managed=no)\n' "$(device_config get bluetooth scan_timeout_millis 2>/dev/null)"
    printf 'resident_process=no\n'
}

collect_diagnostics() {
    tmp="$DIAGNOSTICS.tmp"
    diag_prefix="$MODDIR/.diagnostics.$$"
    thermal_file="$diag_prefix.thermal"
    hint_file="$diag_prefix.hint"
    activity_file="$diag_prefix.activity"
    sf_file="$diag_prefix.sf"
    display_file="$diag_prefix.display"
    telephony_file="$diag_prefix.telephony"

    dumpsys thermalservice > "$thermal_file" 2>/dev/null
    dumpsys performance_hint > "$hint_file" 2>/dev/null
    dumpsys activity > "$activity_file" 2>/dev/null
    dumpsys SurfaceFlinger > "$sf_file" 2>/dev/null
    dumpsys display > "$display_file" 2>/dev/null
    su 2000 -c 'dumpsys telephony.registry' > "$telephony_file" 2>/dev/null

    {
        printf 'Spacewar Daily Profile diagnostics\n'
        printf 'generated=%s\n' "$(date -Ins 2>/dev/null || date)"
        printf 'module_version=%s\n' "$(sed -n 's/^version=//p' "$MODDIR/module.prop" | head -n 1)"
        printf 'android_release=%s\n' "$(getprop ro.build.version.release)"
        printf 'security_patch=%s\n' "$(getprop ro.build.version.security_patch)"
        printf 'kernel=%s\n' "$(uname -r)"
        printf 'page_size=%s\n' "$(getconf PAGE_SIZE 2>/dev/null)"

        printf '\n[profile]\n'
        print_status

        printf '\n[android16_platform]\n'
        printf 'thermal_status=%s\n' "$(sed -n 's/^Thermal Status: //p' "$thermal_file" | head -n 1)"
        printf 'thermal_hal_ready=%s\n' "$(sed -n 's/^HAL Ready: //p' "$thermal_file" | head -n 1)"
        printf 'hint_session_support=%s\n' "$(sed -n 's/^Hint Session Support: //p' "$hint_file" | head -n 1)"
        printf 'cpu_headroom_support=%s\n' "$(sed -n 's/^CPU Headroom Supported: //p' "$hint_file" | head -n 1)"
        printf 'gpu_headroom_support=%s\n' "$(sed -n 's/^GPU Headroom Supported: //p' "$hint_file" | head -n 1)"
        printf 'cached_app_freezer=%s\n' "$(sed -n 's/^[[:space:]]*use_freezer=//p' "$activity_file" | head -n 1)"
        if [ -r /sys/kernel/mm/lru_gen/enabled ]; then
            printf 'mglru=%s\n' "$(read_one_line /sys/kernel/mm/lru_gen/enabled)"
        else
            printf 'mglru=unsupported_by_kernel\n'
        fi

        printf '\n[memory]\n'
        printf 'mem_available_kb=%s\n' "$(awk '/^MemAvailable:/{print $2}' /proc/meminfo 2>/dev/null)"
        printf 'swap_total_kb=%s\n' "$(awk '/^SwapTotal:/{print $2}' /proc/meminfo 2>/dev/null)"
        printf 'swap_free_kb=%s\n' "$(awk '/^SwapFree:/{print $2}' /proc/meminfo 2>/dev/null)"
        if [ -r /sys/block/zram0/comp_algorithm ]; then
            printf 'zram_algorithm=%s\n' "$(active_zram_algorithm)"
            printf 'zram_algorithms_available=%s\n' "$(read_one_line /sys/block/zram0/comp_algorithm)"
            printf 'zram_disksize_bytes=%s\n' "$(read_one_line /sys/block/zram0/disksize)"
            printf 'zram_mm_stat=%s\n' "$(read_one_line /sys/block/zram0/mm_stat)"
            printf 'zram_io_stat=%s\n' "$(read_one_line /sys/block/zram0/io_stat)"
        fi
        printf 'vm_swappiness=%s\n' "$(read_one_line /proc/sys/vm/swappiness)"
        printf 'vm_page_cluster=%s\n' "$(read_one_line /proc/sys/vm/page-cluster)"
        printf 'vm_pswpin=%s\n' "$(awk '/^pswpin /{print $2}' /proc/vmstat 2>/dev/null)"
        printf 'vm_pswpout=%s\n' "$(awk '/^pswpout /{print $2}' /proc/vmstat 2>/dev/null)"
        printf 'vm_major_faults=%s\n' "$(awk '/^pgmajfault /{print $2}' /proc/vmstat 2>/dev/null)"
        printf 'vm_oom_kills=%s\n' "$(awk '/^oom_kill /{print $2}' /proc/vmstat 2>/dev/null)"
        printf 'memory_psi=%s\n' "$(tr '\n' ';' < /proc/pressure/memory 2>/dev/null)"
        printf 'io_psi=%s\n' "$(tr '\n' ';' < /proc/pressure/io 2>/dev/null)"

        printf '\n[display]\n'
        printf 'min_refresh_rate=%s\n' "$(settings get system min_refresh_rate 2>/dev/null)"
        printf 'peak_refresh_rate=%s\n' "$(settings get system peak_refresh_rate 2>/dev/null)"
        printf 'active_panel_hz=%s\n' "$(sed -n 's/.*activeMode=.*vsyncRate=\([0-9.]*\) Hz.*/\1/p' "$sf_file" | head -n 1)"
        printf 'idle_refresh_config=%s\n' "$(sed -n 's/.*idleScreenRefreshRateConfig=\([^}]*\).*/\1/p' "$display_file" | head -n 1)"

        printf '\n[radio]\n'
        printf 'preferred_network_mode=%s\n' "$(settings get global preferred_network_mode 2>/dev/null)"
        printf 'telephony_display=%s\n' "$(sed -n 's/^[[:space:]]*mTelephonyDisplayInfo=//p' "$telephony_file" | tail -n 1)"

        printf '\n[known_rom_gaps]\n'
        [ "$(sed -n 's/^HAL Ready: //p' "$thermal_file" | head -n 1)" = true ] \
            && printf 'thermal_hal_gap=no\n' || printf 'thermal_hal_gap=yes\n'
        [ "$(sed -n 's/^Hint Session Support: //p' "$hint_file" | head -n 1)" = true ] \
            && printf 'adpf_hint_gap=no\n' || printf 'adpf_hint_gap=yes\n'
        grep -q 'idleScreenRefreshRateConfig=null' "$display_file" \
            && printf 'idle_refresh_policy_gap=yes\n' || printf 'idle_refresh_policy_gap=no\n'
    } > "$tmp"

    rm -f "$thermal_file" "$hint_file" "$activity_file" "$sf_file" "$display_file" "$telephony_file"
    mv -f "$tmp" "$DIAGNOSTICS"
    chmod 0644 "$DIAGNOSTICS" 2>/dev/null
    log_message "Collected one-shot Android 16 platform diagnostics."
}
