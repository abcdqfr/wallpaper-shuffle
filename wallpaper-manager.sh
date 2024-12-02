#!/bin/bash
pkill -f linux-wallpaperengine &
KILL_PID=$!

# Helper function to expand ~ to $HOME
expand_path() { echo "${1/#\~/$HOME}"; }

# Wait for kill to complete with timeout
wait $KILL_PID
sleep 0.5

INSTANCE_FILE="$HOME/.config/cinnamon/spices/wallpaper-shuffle@abcdqfr/wallpaper-shuffle@abcdqfr.json"
SCHEMA_FILE="$HOME/.local/share/cinnamon/applets/wallpaper-shuffle@abcdqfr/settings-schema.json"
WALLPAPER_DIR=$(expand_path "$(jq -r '.wallpaperDir.value' "$INSTANCE_FILE" 2>/dev/null || jq -r '.wallpaperDir.default' "$SCHEMA_FILE")")
LINUX_WPE_PATH=$(expand_path "$(jq -r '.linuxWpePath.value' "$INSTANCE_FILE" 2>/dev/null || jq -r '.linuxWpePath.default' "$SCHEMA_FILE")")

# Initialize instance file if it doesn't exist
if [ ! -s "$INSTANCE_FILE" ]; then
    mkdir -p "$(dirname "$INSTANCE_FILE")"
    
    # Create instance file by converting schema defaults to values
    jq '
    def process_value(v):
        if v.type == "header" then
            v
        else
            v + { value: v.default }
        end;

    with_entries(
        select(.key != "head") |
        .value = process_value(.value)
    )' "$SCHEMA_FILE" > "$INSTANCE_FILE"
fi
load_queue() {
    [ ! -d "$WALLPAPER_DIR" ] && echo "Error: Wallpaper directory not found" && return 1
    echo "Debug: Loading wallpapers from $WALLPAPER_DIR"
    
    WALLPAPERS=$(find "$WALLPAPER_DIR" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | jq -R -s 'split("\n")[:-1]')
    echo "Debug: Found wallpapers:"
    echo "$WALLPAPERS"
    
    [ "$WALLPAPERS" = "[]" ] && echo "Error: No wallpapers found in directory" && return 1
    
    # Update the queue structure
    jq --arg list "$WALLPAPERS" '.queue = {"value": ($list | fromjson)}' "$INSTANCE_FILE" > "${INSTANCE_FILE}.tmp" \
        && mv "${INSTANCE_FILE}.tmp" "$INSTANCE_FILE"
    
    echo "Debug: New queue structure:"
    jq '.queue' "$INSTANCE_FILE"
}

# Check if queue needs to be initialized
QUEUE_LENGTH=$(jq -r '.queue.value | length' "$INSTANCE_FILE" 2>/dev/null || echo "0")
echo "Queue length: $QUEUE_LENGTH"
if [ "$QUEUE_LENGTH" -eq 0 ]; then
    load_queue
fi

# Load settings from instance, fall back to schema defaults
SCREEN_ROOT=$(jq -r '.screenRoot.value' "$INSTANCE_FILE" 2>/dev/null || jq -r '.screenRoot.default' "$SCHEMA_FILE")
DISABLE_MOUSE=$(jq -r '.disableMouse.value' "$INSTANCE_FILE" 2>/dev/null || jq -r '.disableMouse.default' "$SCHEMA_FILE")
VOLUME=$(jq -r '.volumeLevel.value' "$INSTANCE_FILE" 2>/dev/null || jq -r '.volumeLevel.default' "$SCHEMA_FILE")
MUTE_AUDIO=$(jq -r '.muteAudio.value' "$INSTANCE_FILE" 2>/dev/null || jq -r '.muteAudio.default' "$SCHEMA_FILE")
SCALING_MODE=$(jq -r '.scalingMode.value' "$INSTANCE_FILE" 2>/dev/null || jq -r '.scalingMode.default' "$SCHEMA_FILE")
CLAMPING_MODE=$(jq -r '.clampingMode.value' "$INSTANCE_FILE" 2>/dev/null || jq -r '.clampingMode.default' "$SCHEMA_FILE")


load_wallpaper() {
    
    INDEX=$(jq -r '.currentIndex.value // .currentIndex.default // 0' "$INSTANCE_FILE")
    echo "Debug: Trying to access index $INDEX"
    
    WALLPAPER=$(jq -r --argjson idx "$INDEX" '.queue.value[$idx] // empty' "$INSTANCE_FILE")
    echo "Debug: Loading wallpaper: $WALLPAPER"
    
    [ -z "$WALLPAPER" ] && echo "Error: Invalid wallpaper ID" && return 1

    # Verify wallpaper directory exists and contains project.json
    FULL_WALLPAPER_PATH="$WALLPAPER_DIR/$WALLPAPER"
    echo "Debug: Checking wallpaper at: $FULL_WALLPAPER_PATH"
    
    cd "$LINUX_WPE_PATH" || return 1
    
    # Export display if not set
    export DISPLAY=${DISPLAY:-:0}
    
    CMD="./linux-wallpaperengine"
    [ -n "$SCALING_MODE" ] && [ "$SCALING_MODE" != "default" ] && CMD+=" --scaling $SCALING_MODE"
    [ -n "$CLAMPING_MODE" ] && [ "$CLAMPING_MODE" != "clamp" ] && CMD+=" --clamping $CLAMPING_MODE"
    [ -n "$SCREEN_ROOT" ] && CMD+=" --screen-root $SCREEN_ROOT"
    { [ "$MUTE_AUDIO" = "true" ] || [ "$VOLUME" = "0" ]; } && CMD+=" --silent"
    [[ "$VOLUME" =~ ^[0-9]+$ ]] && [ "$VOLUME" -ge 0 ] && [ "$VOLUME" -le 100 ] && CMD+=" --volume $VOLUME"
    [ "$DISABLE_MOUSE" = "true" ] && CMD+=" --disable-mouse"
    
    echo "Debug: Running command: $CMD $FULL_WALLPAPER_PATH"
    
    # Run with error redirection
    eval "$CMD $FULL_WALLPAPER_PATH" 2>&1 | tee /tmp/wallpaper-engine.log &
    WPE_PID=$!
    
    # Give it time to start
    sleep 3
    
    # Check if process is still running
    if ! kill -0 $WPE_PID 2>/dev/null; then
        echo "Error: Wallpaper engine failed to start"
        echo "Last few lines of log:"
        tail -n 5 /tmp/wallpaper-engine.log
        return 1
    fi
}

case "$1" in
    load) load_wallpaper ;;
    queue) load_queue ;;
    next|prev) 
        TOTAL=$(jq -r '.queue.value | length' "$INSTANCE_FILE")
        [ "$TOTAL" -eq 0 ] && load_queue && TOTAL=$(jq -r '.queue.value | length' "$INSTANCE_FILE")
        
        if [ "$TOTAL" -eq 0 ]; then
            echo "Error: No wallpapers found. Check your wallpaper directory."
            exit 1
        fi
        
        INDEX=$(jq -r '.currentIndex.value // .currentIndex.default // 0' "$INSTANCE_FILE")
        if [ "$1" = "next" ]; then
            NEW_INDEX=$(( (INDEX + 1) % TOTAL ))
        else
            NEW_INDEX=$(( (INDEX - 1 + TOTAL) % TOTAL ))
        fi
        
        jq --argjson idx "$NEW_INDEX" '.currentIndex.value = $idx' "$INSTANCE_FILE" > "${INSTANCE_FILE}.tmp" \
            && mv "${INSTANCE_FILE}.tmp" "$INSTANCE_FILE" \
            && load_wallpaper
        ;;
    random)
        TOTAL=$(jq -r '.queue.value | length' "$INSTANCE_FILE")
        [ "$TOTAL" -gt 0 ] && jq --argjson idx "$((RANDOM % TOTAL))" '.currentIndex.value = $idx' "$INSTANCE_FILE" > "${INSTANCE_FILE}.tmp" \
            && mv "${INSTANCE_FILE}.tmp" "$INSTANCE_FILE" \
            && load_wallpaper
        ;;
    exit)
        pkill -f linux-wallpaperengine &
        KILL_PID=$!
        wait $KILL_PID
        sleep 1
        cinnamon --replace &
        ;;
    settings)
        jq --arg key "$2" --arg val "$3" 'if .[$key] then .[$key].value = $val else . end' "$INSTANCE_FILE" > "${INSTANCE_FILE}.tmp" \
            && mv "${INSTANCE_FILE}.tmp" "$INSTANCE_FILE" \
            && load_wallpaper
        ;;
    *) echo "Usage: $0 {queue|load|next|prev|random|exit|settings}" ;;
esac
