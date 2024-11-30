#!/bin/bash
pkill -f linux-wallpaperengine
sleep 0.5
SETTINGS_FILE="$HOME/.local/share/cinnamon/applets/wallpaper-shuffle/settings-schema.json"
SCREEN=$(jq -r '.screen.default' "$SETTINGS_FILE")
DISABLE_MOUSE=$(jq -r '.disableMouse.default' "$SETTINGS_FILE")
VOLUME=$(jq -r '.volumeLevel.default' "$SETTINGS_FILE")
expand_tilde() {
    local path="$1"
    if [[ "$path" == "~/"* ]]; then
        echo "${HOME}${path:1}"
    else
        echo "$path"
    fi
}
LINUX_WPE_PATH=$(jq -r '.linuxWPEPath.default' "$SETTINGS_FILE")
LINUX_WPE_PATH=$(expand_tilde "$LINUX_WPE_PATH")
WALLPAPER_DIR=$(jq -r '.wallpaperDir.default' "$SETTINGS_FILE")
WALLPAPER_DIR=$(expand_tilde "$WALLPAPER_DIR")
#QUEUE=$(jq -r '.queue.default' "$SETTINGS_FILE")
CURRENT_INDEX=$(jq -r '.currentIndex.default' "$SETTINGS_FILE")

# Shuffle the wallpaper queue
shuffle_queue() {
    WALLPAPER_LIST=$(find "$WALLPAPER_DIR" -mindepth 1 -maxdepth 1 -type d | shuf | awk -F/ '{print $NF}' | jq -R -s 'split("\n") | map(select(. != ""))')
    jq ".queue.default = $WALLPAPER_LIST" "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
    echo "Shuffle queue updated with last directory names."
}

# Load the current wallpaper and set the volume
load_wallpaper() {
    CURRENT_INDEX=$(jq -r '.currentIndex.default' "$SETTINGS_FILE")
    WALLPAPER_LIST=$(jq -r '.queue.default[]' "$SETTINGS_FILE")
    CURRENT_WALLPAPER=$(echo "$WALLPAPER_LIST" | sed -n "$((CURRENT_INDEX + 1))p")

    if [ -n "$CURRENT_WALLPAPER" ]; then
        cd "$LINUX_WPE_PATH"
        ./linux-wallpaperengine --screen-root "$SCREEN" --volume "$VOLUME" "$CURRENT_WALLPAPER"

        # Update status in the settings file
        QUEUE_LENGTH=$(jq -r '.queue.default | length' "$SETTINGS_FILE")
        SHUFFLE_STATUS=$([[ -n "$TIMER_RUNNING" ]] && echo "Active" || echo "Stopped")

        jq --arg wallpaper "$CURRENT_WALLPAPER" --argjson index "$CURRENT_INDEX" \
           --argjson length "$QUEUE_LENGTH" --arg status "$SHUFFLE_STATUS" \
           '.currentWallpaper.default = $wallpaper |
            .currentIndex.default = $index |
            .queueLength.default = $length |
            .shuffleStatus.default = $status' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"

        echo "Loaded wallpaper: $CURRENT_WALLPAPER with volume: $VOLUME"
    else
        echo "No wallpaper found at the current index."
    fi
}

# Load the next wallpaper
next_wallpaper() {
    TOTAL_WALLPAPERS=$(jq -r '.queue.default | length' "$SETTINGS_FILE")
    if [ "$CURRENT_INDEX" -lt $((TOTAL_WALLPAPERS - 1)) ]; then
        jq '.currentIndex.default += 1' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
    else
        jq '.currentIndex.default = 0' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
    fi
    load_wallpaper
}

# Load the previous wallpaper
prev_wallpaper() {
    if [ "$CURRENT_INDEX" -gt 0 ]; then
        jq '.currentIndex.default -= 1' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
        load_wallpaper
    else
        echo "Already at the first wallpaper."
    fi
}

exit_wallpaper_manager() {
    pkill -f linux-wallpaperengine
    sleep 10
    cinnamon --replace &
}

case "$1" in
    load) load_wallpaper ;;
    shuffle) shuffle_queue ;;
    next) next_wallpaper ;;
    prev) prev_wallpaper ;;
    exit) exit_wallpaper_manager ;;
    *) echo "Usage: $0 {shuffle|load|next|prev|exit}" ;;
esac
