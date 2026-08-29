#!/system/bin/sh

OLDMOD=/data/adb/modules/spacewar-daily-profile

ui_print "- Preserving validated Spacewar Daily Profile baselines"

for name in \
    original_mobile_data_always_on \
    original_sleep_disabled \
    original_device_idle_constants \
    original_bluetooth_scan_timeout \
    .v101-retired-settings-restored \
    .v102-lpm-restored \
    .v109-input-boost-retired; do
    [ -e "$OLDMOD/$name" ] && cp -af "$OLDMOD/$name" "$MODPATH/$name"
done

# Preserve only interaction baselines captured by the corrected v1.0.4 timing.
# Older releases could save an intermediate ROM value and must recapture it.
if [ -e "$OLDMOD/.v104-input-baseline" ]; then
    for name in \
        original_input_boost_freq \
        original_input_boost_ms \
        original_sched_boost_on_input \
        .v104-input-baseline; do
        [ -e "$OLDMOD/$name" ] && cp -af "$OLDMOD/$name" "$MODPATH/$name"
    done
fi

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$MODPATH/customize.sh" 0 0 0755
