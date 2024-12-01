#!/bin/bash
pkill -f linux-wallpaperengine
sleep 0.5
SETTINGS_FILE="$HOME/.local/share/cinnamon/applets/wallpaper-shuffle@abcdqfr/settings-schema.json"

expand_tilde() {
    local path="$1"
    if [[ "$path" == "~/"* ]]; then
        echo "${HOME}${path:1}"
    else
        echo "$path"
    fi
}
# Set default values if not found in settings
LINUX_WPE_PATH=$(jq -r '."linuxWpePath".default' "$SETTINGS_FILE")
LINUX_WPE_PATH=$(expand_tilde "$LINUX_WPE_PATH")
WALLPAPER_DIR=$(jq -r '."wallpaperDir".default' "$SETTINGS_FILE")
WALLPAPER_DIR=$(expand_tilde "$WALLPAPER_DIR")
SCREEN_ROOT=$(jq -r '.screenRoot.default // "DisplayPort-2"' "$SETTINGS_FILE")
DISABLE_MOUSE=$(jq -r '.["disableMouse"].default // false' "$SETTINGS_FILE")
VOLUME=$(jq -r '.["volumeLevel"].default // 50' "$SETTINGS_FILE")


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
    CURRENT_INDEX=$(jq -r '."currentIndex".default' "$SETTINGS_FILE")
    WALLPAPER_LIST=$(jq -r '.queue.default[]' "$SETTINGS_FILE")
    CURRENT_WALLPAPER=$(echo "$WALLPAPER_LIST" | sed -n "$((CURRENT_INDEX + 1))p")
    if [ -n "$CURRENT_WALLPAPER" ]; then
        cd "$LINUX_WPE_PATH"
        ./linux-wallpaperengine --screen-root "$SCREEN_ROOT" --volume "$VOLUME" "$CURRENT_WALLPAPER"

        QUEUE_LENGTH=$(jq -r '.queue.default | length' "$SETTINGS_FILE")
        SHUFFLE_STATUS=$([[ -n "$TIMER_RUNNING" ]] && echo "Active" || echo "Stopped")
        jq --arg wallpaper "$CURRENT_WALLPAPER" --argjson index "$CURRENT_INDEX" \
           --argjson length "$QUEUE_LENGTH" --arg status "$SHUFFLE_STATUS" \
           '."currentWallpaper".default = $wallpaper |
            ."currentIndex".default = $index |
            ."queueLength".default = $length |
            ."shuffleStatus".default = $status' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"

        echo "Loaded wallpaper: $CURRENT_WALLPAPER with volume: $VOLUME"
    fi
}

next_wallpaper() {
    #add logic to set prev wallpaper to current wallpaper
    CURRENT_INDEX=$(jq -r '."currentIndex".default' "$SETTINGS_FILE")
    TOTAL_WALLPAPERS=$(jq -r '.queue.default | length' "$SETTINGS_FILE")
    if [ "$CURRENT_INDEX" -lt $((TOTAL_WALLPAPERS - 1)) ]; then
        jq '."currentIndex".default += 1' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
    else
        jq '."currentIndex".default = 0' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
    fi
    load_wallpaper
}

prev_wallpaper() {
    CURRENT_INDEX=$(jq -r '."currentIndex".default' "$SETTINGS_FILE")
    TOTAL_WALLPAPERS=$(jq -r '.queue.default | length' "$SETTINGS_FILE")
    if [ "$CURRENT_INDEX" -gt 0 ]; then
        jq '."currentIndex".default -= 1' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
    else
        jq --argjson index "$((TOTAL_WALLPAPERS - 1))" '."currentIndex".default = $index' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
    fi
    load_wallpaper
}

random_wallpaper() {
    TOTAL_WALLPAPERS=$(jq -r '.queue.default | length' "$SETTINGS_FILE")
    if [ "$TOTAL_WALLPAPERS" -gt 0 ]; then
        RANDOM_INDEX=$((RANDOM % TOTAL_WALLPAPERS))
        jq --argjson index "$RANDOM_INDEX" '."currentIndex".default = $index' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
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
    random) random_wallpaper ;;
    exit) exit_wallpaper_manager ;;
    *) echo "Usage: $0 {queue|load|next|prev|random|exit}" ;;
esac
