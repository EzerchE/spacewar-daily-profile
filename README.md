# Spacewar Daily Profile

Measured KernelSU power profile created and tested for the Nothing Phone (1) (`Spacewar`) running crDroid 12 / Android 16.

The module consolidates conservative, reversible daily-use changes for idle power behavior while preserving notifications and normal app operation.

## Scope

- Restores low-power/deep-Doze timing behavior
- Allows mobile radio idle when appropriate
- Applies a bounded BLE scan timeout without stopping Tile or notification delivery
- No CPU governor, frequency, GPU, ZRAM, notification-channel, or app whitelist forcing
- No steady-state polling loop

This is an independent community profile, not an official crDroid, Nothing, Qualcomm, or Android configuration. It was created specifically for Spacewar. Other devices may be tested only when their kernel, Android build, and power interfaces are compatible; applying it elsewhere without inspection is unsafe.

Install the ZIP from KernelSU and reboot. Disable or uninstall it from KernelSU to roll back. Use at your own risk and verify notifications after installation.
