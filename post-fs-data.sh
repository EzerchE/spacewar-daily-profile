#!/system/bin/sh

# crDroid 12.11's vendor post-boot script requests "lz4kd", while this
# Spacewar kernel exposes lzo, lzo-rle, lz4 and zstd. Select the supported
# LZ4 algorithm before the ROM initializes zRAM. The later invalid write is
# rejected by the kernel, leaving this valid selection in place.
#
# Safety: never reset, resize, swapoff or modify an already initialized zRAM.

MODDIR=${0%/*}
ZRAM=/sys/block/zram0
LOG="$MODDIR/zram-preselect.log"

algorithm_active() {
    awk '{
        for (i = 1; i <= NF; i++) {
            if ($i ~ /^\[/) {
                gsub(/^\[/, "", $i)
                gsub(/\]$/, "", $i)
                print $i
                exit
            }
        }
    }' "$ZRAM/comp_algorithm" 2>/dev/null
}

{
    printf '%s ' "$(date '+%F %T')"

    if [ ! -r "$ZRAM/comp_algorithm" ] || [ ! -r "$ZRAM/disksize" ]; then
        echo "zRAM interface unavailable; unchanged"
        exit 0
    fi

    if [ "$(cat "$ZRAM/disksize" 2>/dev/null)" != 0 ]; then
        echo "zRAM already initialized with $(algorithm_active); unchanged"
        exit 0
    fi

    if ! grep -qw lz4 "$ZRAM/comp_algorithm" 2>/dev/null; then
        echo "kernel does not expose lz4; unchanged"
        exit 0
    fi

    if ! printf 'lz4\n' > "$ZRAM/comp_algorithm" 2>/dev/null; then
        echo "lz4 preselection failed; ROM fallback retained"
        exit 0
    fi

    if [ "$(algorithm_active)" = lz4 ]; then
        echo "lz4 selected before ROM zRAM initialization"
    else
        echo "lz4 verification failed; ROM fallback retained"
    fi
} > "$LOG" 2>&1
