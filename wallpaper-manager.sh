#!/bin/bash

# Kill any existing linux-wallpaperengine processes
pkill -f linux-wallpaperengine &
KILL_PID=$!

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

# Wait for kill to complete with timeout
wait $KILL_PID
sleep 0.5

INSTANCE_FILE="$HOME/.config/cinnamon/spices/wallpaper-shuffle@abcdqfr/wallpaper-shuffle@abcdqfr.json"
SCHEMA_FILE="$HOME/.local/share/cinnamon/applets/wallpaper-shuffle@abcdqfr/settings-schema.json"
WALLPAPER_DIR=$(expand_path "$(jq -r '.wallpaperDir.value' "$INSTANCE_FILE" 2>/dev/null || jq -r '.wallpaperDir.default' "$SCHEMA_FILE")")
LINUX_WPE_PATH=$(expand_path "$(jq -r '.linuxWpePath.value' "$INSTANCE_FILE" 2>/dev/null || jq -r '.linuxWpePath.default' "$SCHEMA_FILE")")

# Initialize settings from schema
initialize_settings() {
    echo "Initializing settings from schema"
    
    # Safety: Check if schema exists
    if [ ! -f "$SCHEMA_FILE" ]; then
        echo "Error: Schema file not found at $SCHEMA_FILE"
        return 1
    fi
    
    # Safety: Create backup of existing instance file if it exists
    if [ -f "$INSTANCE_FILE" ]; then
        cp "$INSTANCE_FILE" "${INSTANCE_FILE}.backup"
    fi
    
    mkdir -p "$(dirname "$INSTANCE_FILE")"
    
    # Safety: Write to temporary file first
    local tmp_file="${INSTANCE_FILE}.tmp"
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
    )' "$SCHEMA_FILE" > "$tmp_file"
    
    # Safety: Verify the new file is valid JSON before replacing
    if jq '.' "$tmp_file" >/dev/null 2>&1; then
        mv "$tmp_file" "$INSTANCE_FILE"
        echo "Settings initialized successfully"
    else
        echo "Error: Generated settings file is invalid"
        rm -f "$tmp_file"
        # Safety: Restore backup if it exists
        [ -f "${INSTANCE_FILE}.backup" ] && mv "${INSTANCE_FILE}.backup" "$INSTANCE_FILE"
        return 1
    fi
}

# Build queue from wallpaper directory
build_queue() {
    local dir="$1"
    echo "Building queue from $dir"
    
    echo "Current instance file before queue update:"
    cat "$INSTANCE_FILE"
    
    # Safety: Verify directory exists
    if [ ! -d "$dir" ]; then
        echo "Error: Directory not found: $dir"
        return 1
    fi
    
    # Safety: Create temporary file for queue update
    local tmp_file="${INSTANCE_FILE}.tmp"
    WALLPAPERS=$(find "$dir" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | jq -R -s 'split("\n")[:-1]')
    
    if [ "$WALLPAPERS" = "[]" ]; then
        echo "No wallpapers found in directory"
        return 1
    fi
    
    # Safety: Verify we can update the queue before modifying the file
    if ! jq --arg list "$WALLPAPERS" '.queue = {"value": ($list | fromjson)}' "$INSTANCE_FILE" > "$tmp_file"; then
        echo "Error: Failed to update queue"
        rm -f "$tmp_file"
        return 1
    fi
    
    # Safety: Verify the new file is valid JSON before replacing
    if jq '.' "$tmp_file" >/dev/null 2>&1; then
        mv "$tmp_file" "$INSTANCE_FILE"
        echo "Queue updated successfully"
    else
        echo "Error: Generated file is invalid"
        rm -f "$tmp_file"
        return 1
    fi
}

# Ensure everything is properly initialized
ensure_initialized() {
    echo "Checking initialization..."
    local init_needed=0
    
    # 1. Check instance file
    if [ ! -s "$INSTANCE_FILE" ]; then
        echo "Instance file missing or empty"
        init_needed=1
    elif ! jq '.' "$INSTANCE_FILE" >/dev/null 2>&1; then
        echo "Instance file is invalid JSON"
        init_needed=1
    fi
    
    echo "Instance file content:"
    cat "$INSTANCE_FILE"
    
    # Initialize if needed
    if [ $init_needed -eq 1 ]; then
        echo "Initializing..."
        if ! initialize_settings; then
            echo "Failed to initialize settings"
            return 1
        fi
    fi
    
    # 2. Get and verify wallpaper directory
    WALLPAPER_DIR=$(expand_path "$(jq -r '.wallpaperDir.value' "$INSTANCE_FILE" 2>/dev/null || jq -r '.wallpaperDir.default' "$SCHEMA_FILE")")
    if [ -z "$WALLPAPER_DIR" ] || [ ! -d "$WALLPAPER_DIR" ]; then
        echo "Invalid wallpaper directory: $WALLPAPER_DIR"
        return 1
    fi
    
    # 3. Check queue
    QUEUE_LENGTH=$(jq -r '.queue.value | length' "$INSTANCE_FILE" 2>/dev/null || echo "0")
    if [ "$QUEUE_LENGTH" -eq 0 ]; then
        if ! build_queue "$WALLPAPER_DIR"; then
            echo "Failed to build queue"
            return 1
        fi
    fi
    
    return 0
}

# Uncomment to test the new initialization logic
 ensure_initialized || exit 1

# Load settings from instance, fall back to schema defaults
load_settings() {
    local vars="screenRoot disableMouse volumeLevel muteAudio scalingMode clampingMode maxFps noAutomute noAudioProcessing noFullscreenPause windowMode assetsDir"
    for var in $vars; do
        declare -g "${var^^}=$(jq -r ".$var.value // .$var.default" "$INSTANCE_FILE" 2>/dev/null || jq -r ".$var.default" "$SCHEMA_FILE")"
    done
}

load_wallpaper() {
    # Verify instance file before starting
    if ! verify_json_file "$INSTANCE_FILE"; then
        echo "Instance file verification failed"
        return 1
    fi
    
    LINUX_WPE_PATH=$(expand_path "$(jq -r '.linuxWpePath.value' "$INSTANCE_FILE" 2>/dev/null || jq -r '.linuxWpePath.default' "$SCHEMA_FILE")")
    
    if [ -z "$LINUX_WPE_PATH" ] || [ ! -d "$LINUX_WPE_PATH" ]; then
        echo "Invalid linux-wallpaperengine path"
        return 1
    fi

    cd "$LINUX_WPE_PATH" || return 1
    
    # Load all settings before building command
    load_settings
    
    INDEX=$(jq -r '.currentIndex.value // .currentIndex.default // 0' "$INSTANCE_FILE")
    WALLPAPER=$(jq -r --argjson idx "$INDEX" '.queue.value[$idx] // empty' "$INSTANCE_FILE")
    
    if [ -z "$WALLPAPER" ]; then
        echo "Invalid wallpaper ID"
        return 1
    fi

    # Update previous wallpaper before changing
    PREV_WALLPAPER=$(jq -r '.currentWallpaper.value // empty' "$INSTANCE_FILE")
    jq --arg prev "$PREV_WALLPAPER" '.previousWallpaper.value = $prev' "$INSTANCE_FILE" | safe_json_update "$INSTANCE_FILE" || {
        echo "Failed to update previous wallpaper"
        return 1
    }

    # Build command with all supported options
    CMD="./linux-wallpaperengine"

    # Mouse interaction
    if [ "$DISABLEMOUSE" = "true" ]; then
        CMD="$CMD --disable-mouse"
    fi

    # Audio settings
    if [ "$MUTEAUDIO" = "true" ]; then
        CMD="$CMD --silent"
    elif [ -n "$VOLUMELEVEL" ] && [ "$VOLUMELEVEL" -ge 0 ] && [ "$VOLUMELEVEL" -le 100 ] 2>/dev/null; then
        CMD="$CMD --volume $VOLUMELEVEL"
    fi

    # Display settings
    if [ -n "$SCREENROOT" ] && [ "$SCREENROOT" != "null" ]; then
        CMD="$CMD --screen-root $SCREENROOT"
    fi

    # Scaling settings
    if [ -n "$SCALINGMODE" ] && [ "$SCALINGMODE" != "null" ]; then
        case "$SCALINGMODE" in
            "default"|"stretch"|"fit"|"fill")
                CMD="$CMD --scaling $SCALINGMODE"
                ;;
        esac
    fi

    # Clamping settings
    if [ -n "$CLAMPINGMODE" ] && [ "$CLAMPINGMODE" != "null" ]; then
        case "$CLAMPINGMODE" in
            "clamp"|"border"|"repeat")
                CMD="$CMD --clamping $CLAMPINGMODE"
                ;;
        esac
    fi

    # Performance settings
    if [ -n "$MAXFPS" ] && [ "$MAXFPS" != "null" ] && [ "$MAXFPS" -ge 1 ] && [ "$MAXFPS" -le 240 ] 2>/dev/null; then
        CMD="$CMD --fps $MAXFPS"
    fi

    # Audio processing options
    [ "$NOAUTOMUTE" = "true" ] && CMD="$CMD --noautomute"
    [ "$NOAUDIOPROCESSING" = "true" ] && CMD="$CMD --no-audio-processing"
    [ "$NOFULLSCREENPAUSE" = "true" ] && CMD="$CMD --no-fullscreen-pause"

    # Window mode
    if [ -n "$WINDOWMODE" ] && [ "$WINDOWMODE" != "null" ]; then
        CMD="$CMD --window $WINDOWMODE"
    fi

    # Custom assets directory
    if [ -n "$ASSETSDIR" ] && [ "$ASSETSDIR" != "null" ] && [ -d "$ASSETSDIR" ]; then
        CMD="$CMD --assets-dir $ASSETSDIR"
    fi

    # Execute the command
    echo "Executing: $CMD $WALLPAPER"
    eval "$CMD $WALLPAPER" &
    WPE_PID=$!
    
    # Wait briefly to ensure process started
    sleep 0.5
    
    # Verify process is running
    if ! kill -0 $WPE_PID 2>/dev/null; then
        echo "Wallpaper engine failed to start"
        return 1
    fi

    # Update current wallpaper in instance file
    jq --arg wp "$WALLPAPER" '.currentWallpaper.value = $wp' "$INSTANCE_FILE" | safe_json_update "$INSTANCE_FILE" || {
        echo "Failed to update current wallpaper"
        return 1
    }
}

# Add these helper functions at the top of the file
verify_json_file() {
    local file="$1"
    if [ ! -s "$file" ]; then
        echo "Error: File $file is empty or doesn't exist"
        return 1
    fi
    if ! jq '.' "$file" >/dev/null 2>&1; then
        echo "Error: File $file contains invalid JSON"
        return 1
    fi
    return 0
}

safe_json_update() {
    local file="$1"
    local tmp="${file}.tmp"
    local backup="${file}.backup"
    
    # Create backup of current file
    cp "$file" "$backup"
    
    # Write to temp file
    cat > "$tmp"
    
    # Verify temp file is valid JSON
    if verify_json_file "$tmp"; then
        mv "$tmp" "$file"
        rm "$backup"
        return 0
    else
        echo "Error: Invalid JSON update, restoring backup"
        mv "$backup" "$file"
        rm -f "$tmp"
        return 1
    fi
}

case "$1" in
    load) 
        ensure_initialized || exit 1
        load_wallpaper 
        ;;
    queue) 
        ensure_initialized || exit 1
        build_queue "$WALLPAPER_DIR"
        ;;
    next|prev)
        ensure_initialized || exit 1
        
        # Verify instance file before operations
        if ! verify_json_file "$INSTANCE_FILE"; then
            echo "Instance file verification failed"
            exit 1
        fi
        
        # Get current index and total with validation
        INDEX=$(jq -r '.currentIndex.value // 0' "$INSTANCE_FILE")
        TOTAL=$(jq -r '.queue.value | length // 0' "$INSTANCE_FILE")
        
        if [ "$TOTAL" -eq 0 ]; then
            echo "Error: Queue is empty"
            exit 1
        fi
        
        echo "Current index: $INDEX, Total wallpapers: $TOTAL"
        
        # Calculate new index
        if [ "$1" = "next" ]; then
            NEW_INDEX=$(( (INDEX + 1) % TOTAL ))
        else
            NEW_INDEX=$(( (INDEX - 1 + TOTAL) % TOTAL ))
        fi
        
        echo "Moving to index: $NEW_INDEX"
        
        # Update index with safety checks
        jq ".currentIndex.value = $NEW_INDEX" "$INSTANCE_FILE" | safe_json_update "$INSTANCE_FILE" || {
            echo "Failed to update index"
            exit 1
        }
        
        load_wallpaper
        ;;
    random)
        ensure_initialized || exit 1
        TOTAL=$(jq -r '.queue.value | length' "$INSTANCE_FILE")
        [ "$TOTAL" -gt 0 ] && jq --argjson idx "$((RANDOM % TOTAL))" '.currentIndex.value = $idx' "$INSTANCE_FILE" > "${INSTANCE_FILE}.tmp" \
            && mv "${INSTANCE_FILE}.tmp" "$INSTANCE_FILE" \
            && load_wallpaper
        ;;
    settings)
        ensure_initialized || exit 1
        jq --arg key "$2" --arg val "$3" 'if .[$key] then .[$key].value = $val else . end' "$INSTANCE_FILE" > "${INSTANCE_FILE}.tmp" \
            && mv "${INSTANCE_FILE}.tmp" "$INSTANCE_FILE" \
            && load_wallpaper
        ;;
    reinit)
        initialize_settings && build_queue "$WALLPAPER_DIR"
        echo "Settings reinitialized."
        exit 0
        ;;
    exit)
        pkill -f linux-wallpaperengine &
        KILL_PID=$!
        wait $KILL_PID
        sleep 1
        cinnamon --replace &
        ;;
    help|--help|-h)
        help_settings
        ;;
    *) echo "Usage: $0 {queue|load|next|prev|random|exit|settings|help}" ;;
esac
