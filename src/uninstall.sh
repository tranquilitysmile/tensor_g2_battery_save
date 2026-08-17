#!/system/bin/sh

# Restore the topology immediately when uninstalling; reboot restores all
# remaining cpufreq and task-profile defaults.
[ -e /sys/devices/system/cpu/cpu7/online ] && \
    chmod 644 /sys/devices/system/cpu/cpu7/online 2>/dev/null && \
    echo 1 > /sys/devices/system/cpu/cpu7/online 2>/dev/null

for group in background dex2oat; do
    node="/dev/cpuctl/$group/cpu.uclamp.max"
    [ -e "$node" ] || continue
    chmod 644 "$node" 2>/dev/null
    echo max > "$node" 2>/dev/null
done
