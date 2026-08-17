#!/system/bin/sh

MODDIR="${0%/*}"
LOG_FILE="$MODDIR/opt.log"
CONFIG_FILE="$MODDIR/config.txt"

LITTLE_MAX_FREQ=1598000
MID_MAX_FREQ=1836000
BIG_MAX_FREQ=2188000
CPU_GOVERNOR=sched_pixel
SCHEDUTIL_RATE_LIMIT_US=10000
DISABLE_TOUCH_BOOST=0
CPUSET_ISOLATION=1
DYNAMIC_ENFORCEMENT=1
ENFORCE_INTERVAL_SEC=180
BACKGROUND_UCLAMP_MAX=35
DEX2OAT_UCLAMP_MAX=60

log() {
    echo "$(date '+%F %T') $*" >> "$LOG_FILE"
}

# Parse only known keys. The config is data, never root shell code.
load_config() {
    [ -r "$CONFIG_FILE" ] || return
    while IFS='=' read -r key value; do
        value="${value%%#*}"
        value="$(echo "$value" | tr -d '[:space:]')"
        case "$key" in
            LITTLE_MAX_FREQ|MID_MAX_FREQ|BIG_MAX_FREQ|SCHEDUTIL_RATE_LIMIT_US|DISABLE_TOUCH_BOOST|CPUSET_ISOLATION|DYNAMIC_ENFORCEMENT|ENFORCE_INTERVAL_SEC|BACKGROUND_UCLAMP_MAX|DEX2OAT_UCLAMP_MAX)
                case "$value" in ''|*[!0-9]*) continue ;; esac
                eval "$key=\$value"
                ;;
            CPU_GOVERNOR)
                case "$value" in sched_pixel|schedutil|conservative) CPU_GOVERNOR="$value" ;; esac
                ;;
        esac
    done < "$CONFIG_FILE"
}

closest_frequency() {
    policy_path="$1"
    target="$2"
    selected=""
    if [ -r "$policy_path/scaling_available_frequencies" ]; then
        for frequency in $(cat "$policy_path/scaling_available_frequencies"); do
            if [ "$frequency" -le "$target" ]; then
                if [ -z "$selected" ] || [ "$frequency" -gt "$selected" ]; then
                    selected="$frequency"
                fi
            fi
        done
    fi
    [ -n "$selected" ] && echo "$selected" || echo "$target"
}

select_governor() {
    policy_path="$1"
    available="$(cat "$policy_path/scaling_available_governors" 2>/dev/null)"
    if echo "$available" | grep -qw "$CPU_GOVERNOR"; then
        echo "$CPU_GOVERNOR"
    elif echo "$available" | grep -qw sched_pixel; then
        echo sched_pixel
    else
        echo schedutil
    fi
}

apply_policy() {
    policy="$1"
    target="$2"
    path="/sys/devices/system/cpu/cpufreq/$policy"
    [ -d "$path" ] || { log "Missing $policy"; return 1; }

    cap="$(closest_frequency "$path" "$target")"
    governor="$(select_governor "$path")"
    chmod 644 "$path/scaling_max_freq" "$path/scaling_governor" 2>/dev/null
    echo "$cap" > "$path/scaling_max_freq" 2>/dev/null
    echo "$governor" > "$path/scaling_governor" 2>/dev/null

    if [ "$governor" = "schedutil" ] && [ -w "$path/schedutil/rate_limit_us" ]; then
        echo "$SCHEDUTIL_RATE_LIMIT_US" > "$path/schedutil/rate_limit_us" 2>/dev/null
    fi

    eval "${policy}_cap=\$cap"
    log "$policy cap=$cap governor=$governor"
}

enforce_cap() {
    policy="$1"
    cap="$2"
    path="/sys/devices/system/cpu/cpufreq/$policy"
    [ -r "$path/scaling_max_freq" ] || return
    current="$(cat "$path/scaling_max_freq" 2>/dev/null)"

    # Never raise a limit lowered by thermal management.
    if [ -n "$current" ] && [ "$current" -gt "$cap" ]; then
        chmod 644 "$path/scaling_max_freq" 2>/dev/null
        echo "$cap" > "$path/scaling_max_freq" 2>/dev/null
        log "Corrected $policy max $current -> $cap"
    fi
}

apply_cpusets() {
    [ "$CPUSET_ISOLATION" = "1" ] || return
    [ -w /dev/cpuset/background/cpus ] && echo 0-3 > /dev/cpuset/background/cpus
    [ -w /dev/cpuset/restricted/cpus ] && echo 0-3 > /dev/cpuset/restricted/cpus
    log "CPUsets applied: bg/restricted=0-3; system-bg/fg/top-app unchanged"
}

write_uclamp_max() {
    group="$1"
    percent="$2"
    node="/dev/cpuctl/$group/cpu.uclamp.max"
    [ -e "$node" ] || { log "Missing uclamp group $group"; return; }
    case "$percent" in ''|*[!0-9]*) return ;; esac
    [ "$percent" -gt 100 ] && percent=100
    chmod 644 "$node" 2>/dev/null
    echo "${percent}.00" > "$node" 2>/dev/null
    applied="$(cat "$node" 2>/dev/null)"
    log "uclamp $group max=$applied"
}

apply_uclamps() {
    write_uclamp_max background "$BACKGROUND_UCLAMP_MAX"
    write_uclamp_max dex2oat "$DEX2OAT_UCLAMP_MAX"
}

restore_critical_defaults() {
    node=/sys/devices/system/cpu/cpu7/online
    if [ -e "$node" ]; then
        chmod 644 "$node" 2>/dev/null
        echo 1 > "$node" 2>/dev/null
        log "CPU7 restored online=$(cat "$node" 2>/dev/null)"
    fi
    node=/dev/cpuctl/system-background/cpu.uclamp.max
    if [ -e "$node" ]; then
        chmod 644 "$node" 2>/dev/null
        echo max > "$node" 2>/dev/null
        log "system-background uclamp restored=$(cat "$node" 2>/dev/null)"
    fi
}

until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 3; done
sleep 15

: > "$LOG_FILE"
load_config
log "Tensor G2 Battery First Face Safe v12 started on $(getprop ro.product.device)"

restore_critical_defaults
apply_policy policy0 "$LITTLE_MAX_FREQ"
apply_policy policy4 "$MID_MAX_FREQ"
apply_policy policy6 "$BIG_MAX_FREQ"
apply_cpusets
apply_uclamps

if [ "$DISABLE_TOUCH_BOOST" = "1" ]; then
    setprop vendor.powerhal.interaction.boost 0
    setprop sys.powerhal.interaction.boost 0
    [ -w /sys/module/cpu_boost/parameters/input_boost_enabled ] && \
        echo 0 > /sys/module/cpu_boost/parameters/input_boost_enabled
    log "Interaction boost disable requested"
else
    log "Stock interaction boost retained"
fi

if [ "$DYNAMIC_ENFORCEMENT" = "1" ]; then
    case "$ENFORCE_INTERVAL_SEC" in
        ''|*[!0-9]*) ENFORCE_INTERVAL_SEC=180 ;;
    esac
    [ "$ENFORCE_INTERVAL_SEC" -lt 60 ] && ENFORCE_INTERVAL_SEC=60
    while true; do
        sleep "$ENFORCE_INTERVAL_SEC"
        enforce_cap policy0 "$policy0_cap"
        enforce_cap policy4 "$policy4_cap"
        enforce_cap policy6 "$policy6_cap"
    done
fi
