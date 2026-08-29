Spacewar Daily Profile 1.0.9

Purpose
- Keeps the low-risk mobile-radio policy supported by device measurements.
- Corrects crDroid's still-unsupported `lz4kd` zRAM request by selecting the
  kernel-supported LZ4 algorithm before the ROM initializes swap.
- Leaves interaction response entirely to Android Power HAL, uclamp and launch
  hints on the Willays kernel.
- Preserves Bluetooth audio, ViPER4Android, notification delivery, Tile,
  Home Assistant, Tuya, location behavior and application standby policy.

Managed policies
1. Allows the mobile radio to idle while Wi-Fi is active by setting
   mobile_data_always_on=0.
2. At KernelSU post-fs-data time, selects LZ4 only when zRAM is still
   uninitialized and the running kernel explicitly advertises LZ4. The ROM
   remains responsible for zRAM size, mkswap, swapon and VM parameters.

Retired in 1.0.9
- Legacy `cpu_boost` input tuning is retired. The 2026-08-10 Willays kernel no
  longer exposes that interface, and Android's Power HAL remains authoritative.
- Upgrading on an older compatible kernel restores the saved ROM input-boost
  baseline once, then leaves it unmanaged.

Retired in 1.0.2
- The Qualcomm sleep_disabled override is retired. Upgrades restore the saved
  ROM baseline once and then leave this kernel policy unmanaged.
- Reason: an overnight system_server watchdog at 00:55 showed PackageManager
  blocked in an F2FS rename while the same boot logged repeated UFS runtime-PM
  parent-resume failures. Reliability, wake and alarm delivery take priority
  over the small idle-power benefit of forcing deeper Qualcomm LPM states.

Retired in 1.0.1
- The custom device_idle_constants string is restored to its saved pre-module
  value and is no longer managed.
- The 120-second Bluetooth scan timeout is restored to its saved pre-module
  value and is no longer managed.
- Legacy CPU-floor and Google Play services activity-recognition experiment
  code has been removed.

Efficiency and safety
- The boot service performs guarded one-shot changes and exits.
- Baselines are captured only after the ROM's post-boot property actions settle.
- No daemon, polling loop or post-unlock timer remains.
- The LZ4 hook is one-shot and exits before Android reports boot completion.
- No kernel low-power state, CPU governor, CPU maximum, I/O scheduler, UFS,
  F2FS, GPU, thermal, audio, notification, application bucket,
  device-idle whitelist, Doze timing or Bluetooth setting is changed.
- Previously saved legacy input-boost values are used only for one-time
  retirement or uninstall restoration on kernels that still expose the nodes.
- zRAM is never reset, resized or swapped off. If it is already initialized,
  unsupported, or LZ4 selection fails, the hook leaves it unchanged.
- Read-only Android 16 diagnostics remain available on demand.
- The manual status/diagnostics action reports LZ4 compression and effective
  ratios, actual RAM saved, swap occupancy, incompressible pages, zRAM I/O
  errors, PSI pressure, swap traffic, major faults and OOM events. Threshold
  evaluation is read-only and never runs in the background. Short boot or
  application-launch PSI bursts are reported but only sustained full stalls
  across the five-minute window affect the health result.

Manual action
  sh action.sh status
  sh action.sh diagnostics
  sh action.sh sync
  sh action.sh restore
  sh action.sh apply
  sh action.sh stop
