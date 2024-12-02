#!/bin/bash

# Kill function to ensure clean process termination
kill_wpe() {
    pkill -f linux-wallpaperengine
    for i in {1..5}; do
        pgrep -f linux-wallpaperengine >/dev/null || break
        sleep 0.2
    done
    pgrep -f linux-wallpaperengine >/dev/null && pkill -9 -f linux-wallpaperengine
}

# Kill any existing instances
kill_wpe

# Helper function to expand ~ to $HOME
expand_path() { echo "${1/#\~/$HOME}"; }

# Add help_settings function here, before the case statement
help_settings() {
    cat << 'EOF'
    Updates a setting value in the instance file and reloads the wallpaper
    Usage: settings <setting_key> <new_value>
    Example: settings volumeLevel 75

    Possible arguments:
        volumeLevel    0-100 (Audio volume percentage)
        muteAudio      true/false (Mute wallpaper audio)
        disableMouse   true/false (Disable mouse interaction)
        scalingMode    default/stretch/fit/fill (How wallpaper scales to screen)
        clampingMode   clamp/border/repeat (How wallpaper edges are handled)
        maxFps         1-240 (Limit FPS to reduce battery usage)
        noAutomute     true/false (Disable auto-muting when other apps play sound)
        noAudioProcessing true/false (Disable audio processing)
        noFullscreenPause true/false (Prevent pausing when apps go fullscreen)
        windowMode     XxYxWxH (Run in window mode with specific geometry)
        assetsDir      path (Custom assets directory)
EOF
}

INSTANCE_FILE="$HOME/.config/cinnamon/spices/wallpaper-shuffle@abcdqfr/wallpaper-shuffle@abcdqfr.json"
SCHEMA_FILE="$HOME/.local/share/cinnamon/applets/wallpaper-shuffle@abcdqfr/settings-schema.json"

# Helper functions
expand_path() { echo "${1/#\~/$HOME}"; }

verify_json_file() {
    local file="$1"
    [ -s "$file" ] && jq '.' "$file" >/dev/null 2>&1
}

safe_json_update() {
    local file="$1" tmp="${file}.tmp" backup="${file}.backup"
    cp "$file" "$backup" && cat > "$tmp"
    if verify_json_file "$tmp"; then
        mv "$tmp" "$file" && rm "$backup"
    else
        mv "$backup" "$file" && rm -f "$tmp"
        return 1
    fi
}

initialize_settings() {
    [ ! -f "$SCHEMA_FILE" ] && { echo "Schema file not found"; return 1; }
    mkdir -p "$(dirname "$INSTANCE_FILE")"
    echo "Initializing settings from schema..."
    jq 'with_entries(select(.key != "head") | .value = if .value.type == "header" then .value else .value + {value: .value.default} end)' \
        "$SCHEMA_FILE" > "$INSTANCE_FILE"
    [ $? -eq 0 ] || { echo "Failed to create instance file"; return 1; }
    [ -s "$INSTANCE_FILE" ] || { echo "Instance file is empty"; return 1; }
    return $?
}

build_queue() {
    local dir="$1"
    echo "Building queue from $dir..."
    [ ! -d "$dir" ] && { echo "Directory not found: $dir"; return 1; }
    
    WALLPAPERS=$(find "$dir" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | jq -R -s 'split("\n")[:-1]')
    [ "$WALLPAPERS" = "[]" ] && { echo "No wallpapers found in directory"; return 1; }
    
    echo "Found wallpapers, updating instance file..."
    jq --arg list "$WALLPAPERS" '.queue.value = ($list | fromjson)' "$INSTANCE_FILE" > "${INSTANCE_FILE}.tmp" && \
    mv "${INSTANCE_FILE}.tmp" "$INSTANCE_FILE"
    [ $? -eq 0 ] || { echo "Failed to update queue in instance file"; return 1; }
    return $?
}

ensure_initialized() {
    if ! verify_json_file "$INSTANCE_FILE"; then
        initialize_settings || { echo "Failed to initialize settings"; return 1; }
    fi
    
    WALLPAPER_DIR=$(expand_path "$(jq -r '.wallpaperDir.value // .wallpaperDir.default' "$INSTANCE_FILE")")
    [ ! -d "$WALLPAPER_DIR" ] && { echo "Invalid wallpaper directory: $WALLPAPER_DIR"; return 1; }
    
    QUEUE_LENGTH=$(jq -r '.queue.value | length // 0' "$INSTANCE_FILE")
    if [ "$QUEUE_LENGTH" -eq 0 ]; then
        build_queue "$WALLPAPER_DIR" || { echo "Failed to build queue"; return 1; }
    fi
    return 0
}

load_wallpaper() {
    LINUX_WPE_PATH=$(expand_path "$(jq -r '.linuxWpePath.value // .linuxWpePath.default' "$INSTANCE_FILE")")
    [ ! -d "$LINUX_WPE_PATH" ] && return 1
    cd "$LINUX_WPE_PATH" || return 1
    
    # Ensure no other instances are running
    kill_wpe
    
    # Load current wallpaper info
    INDEX=$(jq -r '.currentIndex.value // .currentIndex.default // 0' "$INSTANCE_FILE")
    WALLPAPER=$(jq -r --argjson idx "$INDEX" '.queue.value[$idx] // empty' "$INSTANCE_FILE")
    echo "Loading wallpaper at index $INDEX: $WALLPAPER"
    [ -z "$WALLPAPER" ] && return 1
    
    # Update previous wallpaper
    PREV_WALLPAPER=$(jq -r '.currentWallpaper.value // empty' "$INSTANCE_FILE")
    jq --arg prev "$PREV_WALLPAPER" '.previousWallpaper.value = $prev' "$INSTANCE_FILE" | safe_json_update "$INSTANCE_FILE"
    
    # Build command with settings
    CMD="./linux-wallpaperengine"
    for setting in $(jq -r 'to_entries[] | select(.value.value != null) | "\(.key)=\(.value.value)"' "$INSTANCE_FILE"); do
        key="${setting%%=*}" value="${setting#*=}"
        case "$key" in
            disableMouse) [ "$value" = "true" ] && CMD+=" --disable-mouse" ;;
            muteAudio) [ "$value" = "true" ] && CMD+=" --silent" ;;
            volumeLevel) [[ "$value" =~ ^[0-9]+$ ]] && CMD+=" --volume $value" ;;
            screenRoot) [ -n "$value" ] && CMD+=" --screen-root $value" ;;
            scalingMode) [[ "$value" =~ ^(default|stretch|fit|fill)$ ]] && CMD+=" --scaling $value" ;;
            clampingMode) [[ "$value" =~ ^(clamp|border|repeat)$ ]] && CMD+=" --clamping $value" ;;
            maxFps) [[ "$value" =~ ^[0-9]+$ ]] && CMD+=" --fps $value" ;;
            noAutomute) [ "$value" = "true" ] && CMD+=" --noautomute" ;;
            noAudioProcessing) [ "$value" = "true" ] && CMD+=" --no-audio-processing" ;;
            noFullscreenPause) [ "$value" = "true" ] && CMD+=" --no-fullscreen-pause" ;;
            windowMode) [ -n "$value" ] && CMD+=" --window $value" ;;
            assetsDir) [ -d "$value" ] && CMD+=" --assets-dir $value" ;;
        esac
    done
    
    # Execute and verify
    eval "$CMD $WALLPAPER" &
    WPE_PID=$!
    # Wait up to 1 second for process to start
    for i in {1..10}; do
        kill -0 $WPE_PID 2>/dev/null && break
        sleep 0.1
    done
    kill -0 $WPE_PID 2>/dev/null || return 1
    
    # Update current wallpaper
    jq --arg wp "$WALLPAPER" '.currentWallpaper.value = $wp' "$INSTANCE_FILE" | safe_json_update "$INSTANCE_FILE"
}

# Main command handling
case "$1" in
    load) ensure_initialized && load_wallpaper ;;
    queue) 
        echo "Reinitializing settings..."
        initialize_settings || { echo "Failed to initialize settings"; exit 1; }
        WALLPAPER_DIR=$(expand_path "$(jq -r '.wallpaperDir.value // .wallpaperDir.default' "$INSTANCE_FILE")")
        [ ! -d "$WALLPAPER_DIR" ] && { echo "Invalid wallpaper directory: $WALLPAPER_DIR"; exit 1; }
        echo "Building queue from $WALLPAPER_DIR..."
        build_queue "$WALLPAPER_DIR" || { echo "Failed to build queue from $WALLPAPER_DIR"; exit 1; }
        echo "Queue built successfully"
        ;;
    next|prev)
        ensure_initialized || { echo "Failed to initialize"; exit 1; }
        INDEX=$(jq -r '.currentIndex.value // 0' "$INSTANCE_FILE")
        TOTAL=$(jq -r '.queue.value | length // 0' "$INSTANCE_FILE")
        [ "$TOTAL" -eq 0 ] && { echo "Queue is empty"; exit 1; }
        
        if [ "$1" = "next" ]; then
            NEW_INDEX=$(( (INDEX + 1) % TOTAL ))
        else
            NEW_INDEX=$(( (INDEX - 1 + TOTAL) % TOTAL ))
        fi
        echo "Moving from index $INDEX to $NEW_INDEX (total: $TOTAL)"
        jq --argjson idx "$NEW_INDEX" '.currentIndex.value = $idx' "$INSTANCE_FILE" | safe_json_update "$INSTANCE_FILE" && load_wallpaper
        ;;
    random)
        ensure_initialized || exit 1
        TOTAL=$(jq -r '.queue.value | length' "$INSTANCE_FILE")
        [ "$TOTAL" -gt 0 ] && jq --argjson idx "$((RANDOM % TOTAL))" '.currentIndex.value = $idx' "$INSTANCE_FILE" | safe_json_update "$INSTANCE_FILE" && load_wallpaper
        ;;
    settings)
        ensure_initialized || exit 1
        jq --arg key "$2" --arg val "$3" 'if .[$key] then .[$key].value = $val else . end' "$INSTANCE_FILE" | safe_json_update "$INSTANCE_FILE" && load_wallpaper
        ;;
    reinit) initialize_settings && build_queue "$WALLPAPER_DIR" ;;
    exit) 
        kill_wpe
        cinnamon --replace &
        ;;
    help|--help|-h) help_settings ;;
    *) echo "Usage: $0 {queue|load|next|prev|random|exit|settings|help}" ;;
esac
