#!/system/bin/sh

MODDIR="${0%/*}"
. "$MODDIR/common.sh"

case "${1:-diagnostics}" in
    apply)
        save_baselines
        migrate_retired_settings
        migrate_retired_lpm
        retire_interaction_profile
        apply_static_profile
        ;;
    sync)
        save_baselines
        migrate_retired_settings
        migrate_retired_lpm
        retire_interaction_profile
        apply_static_profile
        ;;
    restore)
        restore_all
        ;;
    status)
        print_status
        ;;
    diagnostics)
        collect_diagnostics
        cat "$DIAGNOSTICS"
        ;;
    stop)
        touch "$STOPFILE"
        ;;
    *)
        echo "Usage: action.sh {apply|sync|restore|status|diagnostics|stop}"
        exit 2
        ;;
esac
