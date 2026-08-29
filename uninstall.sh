#!/system/bin/sh

MODDIR="${0%/*}"
. "$MODDIR/common.sh"

touch "$STOPFILE"
restore_all
log_message "Uninstall requested; saved baselines restored."
