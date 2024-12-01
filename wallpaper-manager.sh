#!/bin/bash
pkill -f linux-wallpaperengine
sleep 0.5
SETTINGS_FILE="$HOME/.local/share/cinnamon/applets/wallpaper-shuffle/settings-schema.json"

# Set default values if not found in settings
SCREEN=$(jq -r '.screen.default // "DisplayPort-2"' "$SETTINGS_FILE")
DISABLE_MOUSE=$(jq -r '.["disable-mouse"].default // false' "$SETTINGS_FILE")
VOLUME=$(jq -r '.["volume-level"].default // 50' "$SETTINGS_FILE")

expand_tilde() {
    local path="$1"
    if [[ "$path" == "~/"* ]]; then
        echo "${HOME}${path:1}"
    else
        echo "$path"
    fi
}

LINUX_WPE_PATH=$(jq -r '."linux-wpe-path".default' "$SETTINGS_FILE")
LINUX_WPE_PATH=$(expand_tilde "$LINUX_WPE_PATH")
WALLPAPER_DIR=$(jq -r '."wallpaper-dir".default' "$SETTINGS_FILE")
WALLPAPER_DIR=$(expand_tilde "$WALLPAPER_DIR")

load_queue() {
    if [ ! -d "$WALLPAPER_DIR" ]; then
        echo "Error: Wallpaper directory not found: $WALLPAPER_DIR"
        exit 1
    fi
    
    WALLPAPER_LIST=$(find "$WALLPAPER_DIR" -mindepth 1 -maxdepth 1 -type d | awk -F/ '{print $NF}' | jq -R -s 'split("\n") | map(select(. != ""))')
    
    if [ -n "$WALLPAPER_LIST" ]; then
        echo "$WALLPAPER_LIST" | jq --arg list "$WALLPAPER_LIST" '.queue.default = ($list | fromjson)' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
        echo "Shuffle queue updated with last directory names."
    else
        echo "Error: No wallpapers found in directory: $WALLPAPER_DIR"
        exit 1
    fi
}

load_wallpaper() {
    CURRENT_INDEX=$(jq -r '."current-index".default' "$SETTINGS_FILE")
    WALLPAPER_LIST=$(jq -r '.queue.default[]' "$SETTINGS_FILE")
    CURRENT_WALLPAPER=$(echo "$WALLPAPER_LIST" | sed -n "$((CURRENT_INDEX + 1))p")
    if [ -n "$CURRENT_WALLPAPER" ]; then
        cd "$LINUX_WPE_PATH"
        ./linux-wallpaperengine --screen-root "$SCREEN" --volume "$VOLUME" "$CURRENT_WALLPAPER" #add back disableMouse here

        QUEUE_LENGTH=$(jq -r '.queue.default | length' "$SETTINGS_FILE")
        SHUFFLE_STATUS=$([[ -n "$TIMER_RUNNING" ]] && echo "Active" || echo "Stopped")
        jq --arg wallpaper "$CURRENT_WALLPAPER" --argjson index "$CURRENT_INDEX" \
           --argjson length "$QUEUE_LENGTH" --arg status "$SHUFFLE_STATUS" \
           '."current-wallpaper".default = $wallpaper |
            ."current-index".default = $index |
            ."queue-length".default = $length |
            ."shuffle-status".default = $status' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"

        echo "Loaded wallpaper: $CURRENT_WALLPAPER with volume: $VOLUME"
    fi
}

next_wallpaper() {
    #add logic to set prev wallpaper to current wallpaper
    TOTAL_WALLPAPERS=$(jq -r '.queue.default | length' "$SETTINGS_FILE")
    if [ "$CURRENT_INDEX" -lt $((TOTAL_WALLPAPERS - 1)) ]; then
        jq '."current-index".default += 1' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
    else
        jq '."current-index".default = 0' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
    fi
    load_wallpaper
}

prev_wallpaper() {
    if [ "$CURRENT_INDEX" -gt 0 ]; then
        jq '."current-index".default -= 1' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
        load_wallpaper
    fi
}

exit_wallpaper_manager() {
    pkill -f linux-wallpaperengine
    sleep 10
    cinnamon --replace &
}

case "$1" in
    load) load_wallpaper ;;
    queue) load_queue ;;
    next) next_wallpaper ;;
    prev) prev_wallpaper ;;
    exit) exit_wallpaper_manager ;;
    *) echo "Usage: $0 {queue|load|next|prev|exit}" ;; #nothing to add here? volume, screen, fps, scaling, window-geometry, disable-mouse, no?
esac
