#!/bin/bash
pkill -f linux-wallpaperengine
sleep 0.5
SETTINGS_FILE="$HOME/.local/share/cinnamon/applets/wallpaper-shuffle/settings-schema.json"
SCREEN=$(jq -r '.screen.default' "$SETTINGS_FILE")
DISABLE_MOUSE=$(jq -r '.disableMouse.default' "$SETTINGS_FILE")
expand_tilde() {
    local path="$1"
    if [[ "$path" == "~/"* ]]; then
        echo "${HOME}${path:1}"  # Replace ~ with $HOME
    else
        echo "$path"  # No change if not starting with ~/
    fi
}
LINUX_WPE_PATH=$(jq -r '.linuxWPEPath.default' "$SETTINGS_FILE")
LINUX_WPE_PATH=$(expand_tilde "$LINUX_WPE_PATH")  # Expand if needed
WALLPAPER_DIR=$(jq -r '.wallpaperDir.default' "$SETTINGS_FILE")
WALLPAPER_DIR=$(expand_tilde "$WALLPAPER_DIR")  # Expand if needed
QUEUE_FILE="/tmp/wallpaper_queue"
CURRENT_INDEX_FILE="/tmp/wallpaper_index"

shuffle_queue() {
    find "$WALLPAPER_DIR" -mindepth 1 -maxdepth 1 -type d | shuf > "$QUEUE_FILE"
    echo 0 > "$CURRENT_INDEX_FILE"  # Reset to the first wallpaper
}

#update_schema() {
#    jq ".currentWallpaper.default = \"$1\" |
#        .previousWallpaper.default = \"$2\" |
#        .currentIndex.default = \"$3\" |
#        .queueLength.default = \"$4\" |
#        .shuffleStatus.default = \"$5\"" "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
#}
#log_event() {
#    if [ "$(jq -r '.loggingEnabled.default' "$SETTINGS_FILE")" == "true" ]; then
#        LOG_FILE=$(jq -r '.logFile.default' "$SETTINGS_FILE")
#        echo "$(date): $1" >> "$LOG_FILE"
#    fi
#}

load_wallpaper() {
    CURRENT_INDEX=$(cat "$CURRENT_INDEX_FILE")
    CURRENT_WALLPAPER=$(sed -n "$((CURRENT_INDEX + 1))p" "$QUEUE_FILE")
    if [ -n "$CURRENT_WALLPAPER" ]; then
        cd "$LINUX_WPE_PATH"
        ./linux-wallpaperengine --screen-root "$SCREEN" "$CURRENT_WALLPAPER"
#        QUEUE_LENGTH=$(wc -l < "$QUEUE_FILE")
#        SHUFFLE_STATUS=$([ -n "$TIMER_RUNNING" ] && echo "Active" || echo "Stopped")
#        update_schema "$CURRENT_WALLPAPER" "$PREVIOUS_WALLPAPER" "$CURRENT_INDEX" "$QUEUE_LENGTH" "$SHUFFLE_STATUS"
#        log_event "Loaded wallpaper: $CURRENT_WALLPAPER"
    else
        echo "No wallpapers left in the queue!"
#        log_event "No wallpapers left in the queue!"
    fi
}

next_wallpaper() {
    CURRENT_INDEX=$(cat "$CURRENT_INDEX_FILE")
    TOTAL_WALLPAPERS=$(wc -l < "$QUEUE_FILE")
    if [ "$CURRENT_INDEX" -lt $((TOTAL_WALLPAPERS - 1)) ]; then
        echo $((CURRENT_INDEX + 1)) > "$CURRENT_INDEX_FILE"
        load_wallpaper
    else
        echo "End of queue reached. Restarting..."
        echo 0 > "$CURRENT_INDEX_FILE"
        load_wallpaper
    fi
}

prev_wallpaper() {
    CURRENT_INDEX=$(cat "$CURRENT_INDEX_FILE")
    if [ "$CURRENT_INDEX" -gt 0 ]; then
        echo $((CURRENT_INDEX - 1)) > "$CURRENT_INDEX_FILE"
        load_wallpaper
    else
        echo "Already at the first wallpaper!"
    fi
}

exit_wallpaper_manager() {
    pkill -f linux-wallpaperengine
    sleep 10
    cinnamon --replace &
}

# Command Handler
case "$1" in
    shuffle) shuffle_queue ;;
    load) load_wallpaper ;;
    next) next_wallpaper ;;
    prev) prev_wallpaper ;;
    pause) pause_shuffle ;;
    resume) resume_shuffle ;;
    *) echo "Usage: $0 {shuffle|load|next|prev|exit}" ;;
esac
