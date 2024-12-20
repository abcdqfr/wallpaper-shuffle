#!/bin/bash

kill_wpe() {
    pkill -f linux-wallpaperengine
    for i in {1..5}; do
        pgrep -f linux-wallpaperengine | grep -v "^$$\$" >/dev/null || break
        sleep 0.2
    done
    pkill -9 -f linux-wallpaperengine 2>/dev/null
    while pgrep -f linux-wallpaperengine >/dev/null; do sleep 0.1; done
}

expand_path() { echo "${1/#\~/$HOME}"; }

help_settings() {
    cat << 'EOF'
Usage: ./wallpaper-manager.sh <command> [options]

Basic Commands:
    queue               Build/rebuild wallpaper queue from wallpaperDir
    next               Switch to next wallpaper in queue
    prev               Switch to previous wallpaper in queue
    random             Switch to random wallpaper from queue
    exit               Kill wallpaper engine and restore Cinnamon

Load Command:
    load               Load current wallpaper from queue
    load <id>          Load specific wallpaper by ID

Settings Command:
    settings <key> <value>    Change a setting

Available Settings:
    Path Settings:
        wallpaperDir         Path to directory containing wallpapers
        linuxWpePath         Path to linux-wallpaperengine build
        screenRoot           Display output name for wallpaper

    Display Settings:
        scalingMode          default | stretch | fit | fill
        clampingMode         clamp | border | repeat
        maxFps              1-240 (FPS limit)

    Audio Settings:
        volumeLevel         0-100 (volume percentage)
        muteAudio           true | false
        noAutomute          true | false
        noAudioProcessing   true | false

Commands:
    queue                   Build/rebuild wallpaper queue from wallpaperDir
    load [wallpaper_id]     Load wallpaper (current or specified ID)
    next                    Switch to next wallpaper in queue
    prev                    Switch to previous wallpaper in queue
    random                  Switch to random wallpaper from queue
    exit                    Kill wallpaper engine and restore Cinnamon
    settings <key> <value>  Change a setting

Settings:
    wallpaperDir    path    (Directory containing wallpapers)
    linuxWpePath    path    (Path to linux-wallpaperengine build)
    screenRoot      name    (Display output for wallpaper)
    volumeLevel     0-100   (Audio volume percentage)
    muteAudio       true/false (Mute wallpaper audio)
    disableMouse    true/false (Disable mouse interaction)
    scalingMode     default/stretch/fit/fill (How wallpaper scales)
    clampingMode    clamp/border/repeat (Edge handling)
    maxFps          1-240   (FPS limit for battery saving)
    noAutomute      true/false (Disable auto-muting)
    noAudioProcessing true/false (Disable audio processing)
    noFullscreenPause true/false (Prevent fullscreen pause)
    currentIndex    number  (Current position in queue)
    currentWallpaper id    (Current wallpaper ID)

Examples:
    ./wallpaper-manager.sh load 1234567890
    ./wallpaper-manager.sh settings volumeLevel 50
    ./wallpaper-manager.sh next
EOF
}

SETTINGS_FILE="$HOME/.local/share/cinnamon/applets/wallpaper-shuffle@abcdqfr/settings-schema.json"

get_setting() {
    [ -f "$SETTINGS_FILE" ] && value=$(jq -r ".$1.value // .$1.default // \"$2\"" "$SETTINGS_FILE") || value="$2"
    if [ "$1" = "queue" ]; then
        echo "[\"${value//,/\",\"}\"]"
    else
        [ "$value" = "null" ] && echo "$2" || echo "$value"
    fi
}

set_setting() {
    [ ! -f "$SETTINGS_FILE" ] && echo "{}" > "$SETTINGS_FILE"
    local temp_file=$(mktemp)
    local numeric_keys='["volumeLevel", "maxFps", "shuffleInterval"]'
    local value_convert='if ($key | IN($numeric_keys[])) then (try ($value | tonumber) catch $value) else $value end'
    
    if jq --arg key "$1" --arg value "$2" \
        --argjson numeric_keys "$numeric_keys" \
        'if has($key) then
            .[$key] = (
                if .[$key] | type == "object" then
                    .[$key] * {"value": ('"$value_convert"')}
                else
                    {"type": "generic", "value": ('"$value_convert"')}
                end
            )
         else
            .[$key] = {"type": "generic", "value": ('"$value_convert"')}
         end' "$SETTINGS_FILE" > "$temp_file"; then
        mv "$temp_file" "$SETTINGS_FILE"
    else
        echo "Error: Failed to update settings for $1" >&2
        rm "$temp_file"
    fi
}

build_queue() {
    [ ! -d "$1" ] && return 1
    local wallpapers=$(find "$1" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | tr '\n' ',' | sed 's/,$//')
    [ -n "$wallpapers" ] && set_setting "queue" "$wallpapers"
}

check_queue() {
    local dir=$(expand_path "$(get_setting "wallpaperDir" "$HOME/.steam/debian-installation/steamapps/workshop/content/431960")")
    local dir_count=$(find "$dir" -mindepth 1 -maxdepth 1 -type d | wc -l)
    local queue_count=$(get_setting "queue" "[]" | jq '. | length')
    
    # Rebuild if queue is empty or counts don't match
    [ "$queue_count" = "0" ] || [ "$dir_count" != "$queue_count" ] && build_queue "$dir"
}

load_wallpaper() {
    LINUX_WPE_PATH=$(expand_path "$(get_setting "linuxWpePath" "$HOME/linux-wallpaperengine/build")")
    [ ! -d "$LINUX_WPE_PATH" ] && return 1
    cd "$LINUX_WPE_PATH" || return 1
    
    kill_wpe
    
    # Check queue before loading
    check_queue
    
    INDEX=$(get_setting "currentIndex" "0")
    QUEUE=$(get_setting "queue" "[]")
    WALLPAPER=$(echo "$QUEUE" | jq -r ".[$INDEX]" 2>/dev/null)
    [ -z "$WALLPAPER" ] || [ "$WALLPAPER" = "null" ] && return 1
    
    CMD="./linux-wallpaperengine"
    [ "$(get_setting "disableMouse" "false")" = "true" ] && CMD+=" --disable-mouse"
    
    VOL=$(get_setting "volumeLevel" "50")
    if [ "$(get_setting "muteAudio" "false")" = "true" ]; then
        CMD+=" --silent"
    elif [ -n "$VOL" ]; then
        VOL=$(printf "%.0f" "$VOL")
        CMD+=" --volume ${VOL}"
    fi
    
    SCREEN=$(get_setting "screenRoot" "")
    [ -z "$SCREEN" ] || [ "$SCREEN" = "null" ] && SCREEN=$(xrandr --listmonitors | grep '+' | head -n1 | awk '{print $NF}')
    CMD+=" --screen-root $SCREEN"
    
    SCALING=$(get_setting "scalingMode" "default")
    [[ "$SCALING" =~ ^(default|stretch|fit|fill)$ ]] && CMD+=" --scaling $SCALING"
    
    CLAMPING=$(get_setting "clampingMode" "clamp")
    [[ "$CLAMPING" =~ ^(clamp|border|repeat)$ ]] && CMD+=" --clamping $CLAMPING"
    
    FPS=$(get_setting "maxFps" "60")
    [[ "$FPS" =~ ^[0-9]+$ ]] && [ "$FPS" -ge 1 ] && [ "$FPS" -le 240 ] && CMD+=" --fps $FPS"
    
    [ "$(get_setting "noAutomute" "false")" = "true" ] && CMD+=" --noautomute"
    [ "$(get_setting "noAudioProcessing" "false")" = "true" ] && CMD+=" --no-audio-processing"
    [ "$(get_setting "noFullscreenPause" "false")" = "true" ] && CMD+=" --no-fullscreen-pause"
    
    eval "$CMD $WALLPAPER" &
    
    PREV_WALLPAPER=$(get_setting "currentWallpaper" "")
    set_setting "previousWallpaper" "$PREV_WALLPAPER"
    set_setting "currentWallpaper" "$WALLPAPER"
}

case "$1" in
    load) load_wallpaper ;;
    queue) build_queue "$(expand_path "$(get_setting "wallpaperDir" "$HOME/.steam/debian-installation/steamapps/workshop/content/431960")")" ;;
    next|prev)
        check_queue  # Check queue before navigation
        INDEX=$(get_setting "currentIndex" "0")
        QUEUE=$(get_setting "queue" "[]")
        INDEX=${INDEX:-0}
        [[ "$INDEX" =~ ^[0-9]+$ ]] || INDEX=0
        
        TOTAL=$(echo "$QUEUE" | jq -r '. | length' 2>/dev/null)
        [ -z "$TOTAL" ] || [ "$TOTAL" = "null" ] || ! [[ "$TOTAL" =~ ^[0-9]+$ ]] && exit 1
        [ "$TOTAL" -eq 0 ] && exit 1
        
        if [ "$1" = "next" ]; then
            NEW_INDEX=$(( (INDEX + 1) % TOTAL ))
        else
            NEW_INDEX=$(( (INDEX - 1 + TOTAL) % TOTAL ))
        fi
        
        set_setting "currentIndex" "$NEW_INDEX"
        load_wallpaper ;;
    random) 
        check_queue  # Check queue before random selection
        TOTAL=$(get_setting "queue" | jq '. | length') && \
        [ "$TOTAL" -gt 0 ] && \
        set_setting "currentIndex" "$((RANDOM % TOTAL))" && \
        load_wallpaper ;;
    settings)
        kill_wpe
        case "$2" in
            volumeLevel) [[ "$3" =~ ^[0-9]+\.?[0-9]*$ ]] && VOL=$(printf "%.0f" "$3") && [ "$VOL" -ge 0 ] && [ "$VOL" -le 100 ] && set_setting "$2" "$VOL" && load_wallpaper ;;
            maxFps) [[ "$3" =~ ^[0-9]+$ ]] && [ "$3" -ge 1 ] && [ "$3" -le 240 ] && set_setting "$2" "$3" && load_wallpaper ;;
            shuffleInterval) [[ "$3" =~ ^[0-9]+$ ]] && [ "$3" -ge 1 ] && [ "$3" -le 1440 ] && set_setting "$2" "$3" ;;
            muteAudio|disableMouse|noAutomute|noAudioProcessing|noFullscreenPause) set_setting "$2" "$(echo "$3" | tr '[:upper:]' '[:lower:]' | grep -E '^(true|1)$' >/dev/null && echo true || echo false)" && load_wallpaper ;;
            scalingMode) [[ "$3" =~ ^(default|stretch|fit|fill)$ ]] && set_setting "$2" "$3" && load_wallpaper ;;
            clampingMode) [[ "$3" =~ ^(clamp|border|repeat)$ ]] && set_setting "$2" "$3" && load_wallpaper ;;
            *) [ -n "$3" ] && set_setting "$2" "$3" && load_wallpaper ;;
        esac ;;
    exit) kill_wpe; cinnamon --replace & ;;
    help|--help|-h) help_settings ;;
    load-id)
        kill_wpe  # Kill existing wallpaper first
        set_setting "currentWallpaper" "$2"
        load_wallpaper
        ;;
    *) echo "Usage: $0 {queue|load|next|prev|random|exit|settings|help}" ;;
esac
