#!/system/bin/sh

MODDIR="${0%/*}"
. "$MODDIR/common.sh"

rm -f "$STOPFILE"

waited=0
while [ "$(getprop sys.boot_completed 2>/dev/null)" != 1 ] && [ "$waited" -lt 180 ]; do
    sleep 1
    waited=$((waited + 1))
done

if [ "$(getprop sys.boot_completed 2>/dev/null)" != 1 ]; then
    log_message "Boot wait timed out; profile not started."
    exit 0
fi

waited=0
while [ "$(getprop vendor.post_boot.parsed 2>/dev/null)" != 1 ] && [ "$waited" -lt 30 ]; do
    sleep 1
    waited=$((waited + 1))
done

# The property can be set before every init action has finished. Let the ROM's
# final interaction defaults land before preserving uninstall baselines.
sleep 3
save_baselines
touch "$INPUT_BASELINE_V104"
migrate_retired_settings
migrate_retired_lpm
retire_interaction_profile
sleep 30
apply_static_profile
log_message "Started v1.0.9 profile; service exited. LZ4 was selected safely at pre-init; radio-idle policy and on-demand zRAM diagnostics remain active. CPU, LPM, zRAM size, UFS, I/O scheduler, Doze, Bluetooth, notifications, audio and GPU remain otherwise unmanaged."
