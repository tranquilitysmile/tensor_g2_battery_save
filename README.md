<div align="center">

# Tensor G2 CPU Battery Save Mod

**An aggressive, battery-first CPU profile for Google Tensor G2 that keeps critical biometric and system services safe.**

![Version 12](https://img.shields.io/badge/version-12.0-009688)
![Tensor G2](https://img.shields.io/badge/SoC-Google%20Tensor%20G2-4285F4?logo=google&logoColor=white)
![Root module](https://img.shields.io/badge/type-root%20module-E53935)

</div>

> [!IMPORTANT]
> This profile is designed specifically for **Google Tensor G2 (`gs201`)** and
> was developed on the first-generation Pixel Fold (`felix`). Do not install it
> on a different SoC. CPU frequency policy names and scheduler groups are
> device-specific.

## Overview

Tensor G2 CPU Battery Save v12 reduces active and standby power consumption by
capping all three CPU clusters and restricting ordinary background workloads.
The profile gives battery life priority over peak benchmark performance while
retaining stock interaction boost and Google's scheduler for acceptable UI
responsiveness and stable high-refresh-rate behavior.


## Default Profile

### CPU clusters

| Policy | Tensor G2 cluster | CPUs | Stock peak* | v12 maximum | Reduction |
| --- | --- | ---: | ---: | ---: | ---: |
| `policy0` | 4x Cortex-A55 efficiency cores | 0-3 | ~1.85 GHz | **1.598 GHz** | ~14% |
| `policy4` | 2x Cortex-A78 middle cores | 4-5 | ~2.35 GHz | **1.836 GHz** | ~22% |
| `policy6` | 2x Cortex-X1 performance cores | 6-7 | ~2.85 GHz | **2.188 GHz** | ~23% |

\* Stock frequencies can vary slightly by firmware and kernel. If a configured
frequency is unavailable, the script safely selects the closest supported value
at or below the requested cap.

### Scheduler and boosting

| Setting | v12 value | Behavior |
| --- | --- | --- |
| CPU governor | `sched_pixel` | Keeps Google's Pixel-aware scheduler behavior. |
| Governor fallback | `schedutil` | Used only when `sched_pixel` is unavailable. |
| Schedutil rate limit | `10000 us` | Applied only when the fallback governor is active. |
| Touch/interaction boost | Enabled (stock) | Preserves short UI bursts; frequency caps still limit their cost. |
| Display refresh rate | Unchanged | The module does not force 60 Hz or disable Smooth Display. |

### CPU sets

| Android task group | Allowed CPUs | v12 behavior |
| --- | --- | --- |
| `background` | `0-3` | Ordinary background apps remain on efficiency cores. |
| `restricted` | `0-3` | Restricted apps remain on efficiency cores. |
| `system-background` | Stock | Not restricted, protecting system and Trusty-related work. |
| `foreground` | Stock | Foreground apps can use all CPUs as Android decides. |
| `top-app` | Stock | The visible app retains full scheduler placement. |

### Scheduler capacity limits

| cgroup | `cpu.uclamp.max` | Purpose |
| --- | ---: | --- |
| `background` | **35%** | Prevents ordinary background work from requesting high CPU capacity. |
| `dex2oat` | **60%** | Reduces power and heat during background app compilation. |
| `system-background` | **max / stock** | Explicitly restored to protect critical system services. |
| Foreground and top-app | Stock | No v12 capacity ceiling is applied. |

### Runtime enforcement

| Setting | Value | Details |
| --- | ---: | --- |
| Dynamic enforcement | Enabled | Rechecks the three CPU maximum-frequency nodes. |
| Check interval | 180 seconds | Low-frequency polling avoids unnecessary wakeups. |
| Thermal handling | Never raises a lower limit | A cap reduced by thermal management is left untouched. |
| CPU hotplug | Disabled | Both performance cores remain online. |


## Installation

1. Copy `Tensor-G2-CPU-Battery-Save-v12.zip` to the phone.
2. Install it from your root manager's module screen (tested with APatch-style
   module installation).
3. **Reboot the phone.** A reboot is required to stop any older service script
   and recreate Android's stock task groups.
4. Check the module log at `opt.log` after boot.


## Configuration

Edit `config.txt` inside the installed module directory, then reboot. Frequencies
are specified in kHz.

| Key | Default | Accepted values | Description |
| --- | ---: | --- | --- |
| `LITTLE_MAX_FREQ` | `1598000` | Positive integer | Maximum for `policy0`. |
| `MID_MAX_FREQ` | `1836000` | Positive integer | Maximum for `policy4`. |
| `BIG_MAX_FREQ` | `2188000` | Positive integer | Maximum for `policy6`. |
| `CPU_GOVERNOR` | `sched_pixel` | `sched_pixel`, `schedutil`, `conservative` | Preferred governor. |
| `SCHEDUTIL_RATE_LIMIT_US` | `10000` | Positive integer | Fallback governor response interval. |
| `DISABLE_TOUCH_BOOST` | `0` | `0` or `1` | `1` requests interaction-boost disable; less smooth. |
| `CPUSET_ISOLATION` | `1` | `0` or `1` | Applies only background/restricted CPU sets. |
| `DYNAMIC_ENFORCEMENT` | `1` | `0` or `1` | Periodically restores CPU caps raised by PowerHAL. |
| `ENFORCE_INTERVAL_SEC` | `180` | Integer, minimum 60 | Frequency-cap check interval. |
| `BACKGROUND_UCLAMP_MAX` | `35` | `0-100` | Capacity ceiling for ordinary background apps. |
| `DEX2OAT_UCLAMP_MAX` | `60` | `0-100` | Capacity ceiling for dex2oat compilation. |

The parser accepts only known keys and numeric values. `config.txt` is treated as
data and is never sourced as unrestricted root shell code.

## Expected Trade-offs

| Workload | Expected result |
| --- | --- |
| Standby and light use | Lower CPU background demand and improved efficiency. |
| Messaging, browsing and UI | Generally responsive; stock boost is retained. |
| Sustained gaming | Lower peak performance and potentially reduced frame rate. |
| Camera processing | Some operations may complete more slowly. |
| App installation/optimization | Reduced heat, but longer dex2oat completion time. |
| Benchmarks | Significantly lower scores by design. |
| 120 Hz display mode | Not disabled, although heavy workloads may miss frames sooner. |

## Verification

After reboot, inspect the log:

```sh
cat /data/adb/modules/tensor_g2_cpu_opt_v9/opt.log
```

Typical successful entries include:

```text
CPU7 restored online=1
system-background uclamp restored=max
policy0 cap=1598000 governor=sched_pixel
policy4 cap=1836000 governor=sched_pixel
policy6 cap=2188000 governor=sched_pixel
CPUsets applied: bg/restricted=0-3; system-bg/fg/top-app unchanged
uclamp background max=35.00
uclamp dex2oat max=60.00
Stock interaction boost retained
```

You can also check the active limits:

```sh
for policy in policy0 policy4 policy6; do
  path=/sys/devices/system/cpu/cpufreq/$policy
  echo "$policy: $(cat $path/scaling_max_freq) $(cat $path/scaling_governor)"
done

cat /sys/devices/system/cpu/cpu7/online
cat /dev/cpuset/background/cpus
cat /dev/cpuset/restricted/cpus
cat /dev/cpuctl/background/cpu.uclamp.max
cat /dev/cpuctl/system-background/cpu.uclamp.max
```

Transient monitoring tools may display instantaneous or cached frequencies in a
confusing way. `scaling_max_freq` is the authoritative configured ceiling; the
module's 180-second loop corrects limits raised above it by PowerHAL.

## Uninstallation and Recovery

1. Disable or uninstall the module in the root manager.
2. Reboot to restore the kernel, cpufreq and Android task-profile defaults.

The uninstall script immediately brings CPU7 online and removes the two uclamp
ceilings where possible. A reboot remains necessary for a complete stock reset.


## Source Layout

```text
src/
├── module.prop
├── config.txt
├── customize.sh
├── service.sh
├── uninstall.sh
└── META-INF/com/google/android/
    ├── update-binary
    └── updater-script
```

| File | Purpose |
| --- | --- |
| `module.prop` | Module identity, version and description. |
| `config.txt` | User-editable battery profile. |
| `service.sh` | Boot-time application and periodic cap enforcement. |
| `customize.sh` | Installer output and file permissions. |
| `uninstall.sh` | Immediate recovery of critical CPU/uclamp settings. |
| `META-INF` | Flashable module installer entry points. |

## Package Information

| Item | Value |
| --- | --- |
| Display name | Tensor G2 Battery  |
| Module ID | `tensor_g2_cpu_opt_v9` |
| Version | `v12.0` |
| Version code | `1200` |
| Release archive | `Tensor-G2-CPU-Battery-Save-v12.zip` |
| SHA-256 | `64bf5a3bcf073d2c4f9b1471be0b4ee99725068a5e09911e49c1e7d246b17129` |

## Safety Notice

CPU scheduler and frequency changes can affect stability, performance, thermal
behavior and biometric services. Keep a recovery path and test changes one at a
time. This profile intentionally avoids undervolting, thermal-service bypasses,
forced CPU hotplug and restrictions on critical system groups.

---
