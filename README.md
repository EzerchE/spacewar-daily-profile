# Spacewar Daily Profile

Conservative KernelSU power profile for the Nothing Phone (1) (`Spacewar`)
running crDroid 12 / Android 16.

Version 1.0.9 keeps only two measured, low-risk policies:

- Sets `mobile_data_always_on=0`, allowing the mobile radio to idle while Wi-Fi
  is active.
- Selects kernel-supported LZ4 for zRAM before Android initializes swap. The
  ROM remains responsible for zRAM size, VM settings, `mkswap` and `swapon`.

The module does not tune CPU/GPU frequencies or governors, UFS/F2FS, I/O
schedulers, thermal policy, display refresh, audio, Doze timing, notification
channels, application buckets or device-idle whitelists. It has no resident
daemon or polling loop.

Earlier experimental Qualcomm sleep, custom Doze/BLE and legacy input-boost
changes have been retired. Upgrades restore any saved baseline and leave those
interfaces to the ROM and kernel.

Install `spacewar-daily-profile-v1.0.9.zip` from KernelSU and reboot. The module
action provides read-only zRAM, PSI, swap, fault and OOM diagnostics. Disable or
uninstall the module to roll back its managed settings.

This is an independent community profile, not an official crDroid, Nothing,
Qualcomm or Android configuration. It was created and tested on Spacewar.
Other devices should use it only after verifying compatible kernel and Android
interfaces. Use at your own risk and keep a recovery path.
