const { Gio } = imports.gi;
const Applet = imports.ui.applet;
const Mainloop = imports.mainloop;
const Settings = imports.ui.settings;
const PopupMenu = imports.ui.popupMenu;
const WALLPAPER_MANAGER_PATH = `${__dirname}/wallpaper-manager.sh`;
class WallpaperShuffleApplet extends Applet.TextIconApplet {
    constructor(metadata, orientation, panelHeight, instanceId) {
        global.log('WallpaperShuffleApplet: Constructor started');
        global.log(`metadata: ${JSON.stringify(metadata)}`);
        global.log(`instanceId: ${instanceId}`);
        super(orientation, panelHeight, instanceId);
        try {
            this.settings = new Settings.AppletSettings(this, metadata.uuid, instanceId);
            global.log('Settings instance created successfully');
            
            global.log('Initial wallpaperDir value:', this.wallpaperDir);
            
            if (!this.wallpaperDir) {
                global.logError('No wallpaper directory configured');
            }
            
            this._bindSettings();
        } catch (e) {
            global.logError('Failed to initialize applet settings: ' + e.message);
        }
        this.set_applet_icon_name("preferences-desktop-wallpaper");
        this.set_applet_tooltip("Wallpaper Shuffle Controls");
        this.menuManager = new PopupMenu.PopupMenuManager(this);
        this.menu = new Applet.AppletPopupMenu(this, orientation);
        this.menuManager.addMenu(this.menu);
        this.menu.addMenuItem(new Applet.MenuItem("Toggle Timer", null, () => this._toggleTimer()));
        ["next", "prev", "random", "exit"].forEach(cmd => this._addMenuItem(cmd));
        this.actor.connect("button-press-event", () => this.menu.toggle());
    }
    _bindSettings() {
        const properties = [
            "shuffleInterval",
            "volumeLevel",
            "muteAudio",
            "screenRoot",
            "linuxWpePath",
            "wallpaperDir",
            "disableMouse",
            "currentIndex",
            "scalingMode",
            "clampingMode"
        ];
        for (const prop of properties) {
            try {
                this.settings.bindProperty(
                    Settings.BindingDirection.IN,
                    prop,
                    prop,
                    () => {
                        global.log(`Setting ${prop} changed to: ${this[prop]}`);
                        this._applySettings();
                    },
                    null
                );
            } catch (e) {
                global.logError(`Failed to bind ${prop}: ${e.message}`);
            }
        }
    }
    _runCommandAsync(command) {
        try {
            let proc = Gio.Subprocess.new(
                ['/bin/bash', '-c', command],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE
            );
            
            if (!proc) {
                global.logError(`Failed to create subprocess for command: ${command}`);
                return;
            }

            proc.communicate_async(null, null, (proc, res) => {
                try {
                    let [ok, stdout, stderr] = proc.communicate_finish(res);
                    if (!ok) {
                        global.logError(`Command failed: ${stderr.toString().trim()}`);
                        return;
                    }
                    
                    let output = stdout.toString().trim();
                    if (output) {
                        global.log(`Command output: ${output}`);
                    }
                } catch (err) {
                    global.logError(`Command execution failed: ${err.message}`);
                }
            });
        } catch (err) {
            global.logError(`Failed to run command: ${err.message}`);
        }
    }
    _addMenuItem(command) {
        this.menu.addMenuItem(new Applet.MenuItem(command.charAt(0).toUpperCase() + command.slice(1), null, () => this._runCommandAsync(`${WALLPAPER_MANAGER_PATH} ${command}`)));
    }
    _updateStatus() {
        const settingsPath = `${GLib.get_home_dir()}/.cinnamon/configs/wallpaper-shuffle@abcdqfr/settings.json`;
        const file = Gio.file_new_for_path(settingsPath);
        
        file.load_contents_async(null, (aFile, aResponse) => {
            try {
                let [success, contents, tag] = aFile.load_contents_finish(aResponse);
                if (!success) {
                    global.logError("Error reading settings.json");
                    return;
                }
                
                const settings = JSON.parse(contents.toString());
                this.set_applet_tooltip(`Current: ${settings.currentWallpaper.value}`);
                
            } catch (err) {
                global.logError("Failed to parse settings.json: " + err.message);
            }
        });
    }
    _toggleTimer() {
        this.timer ? this._stopTimer() : this._startTimer();
    }
    _startTimer() {
        if (this.timer) {
            this._stopTimer(); // Clean up existing timer first
        }
        
        this.remaining = this.shuffleInterval * 60;
        this.timer = Mainloop.timeout_add_seconds(1, () => {
            try {
                if (this.remaining > 0) {
                    this.remaining--;
                    this._updateTooltip();
                    return true; // Continue timer
                } else {
                    this._runCommandAsync(`${WALLPAPER_MANAGER_PATH} next`);
                    this.remaining = this.shuffleInterval * 60;
                    this._updateTooltip("Timer reset");
                    return true; // Continue timer
                }
            } catch (e) {
                global.logError('Timer error:', e.message);
                this._stopTimer(); // Clean up on error
                return false; // Stop timer
            }
        });
        
        this._updateTooltip("Timer started");
    }
    _stopTimer() {
        if (this.timer) {
            Mainloop.source_remove(this.timer);
            this.timer = null;
            this.remaining = 0;
        }
        this._updateTooltip("Timer stopped");
    }
    _applySettings() {
        try {
            const settings = {
                volumeLevel: parseInt(this.volumeLevel),
                muteAudio: this.muteAudio,
                screenRoot: this.screenRoot,
                disableMouse: this.disableMouse,
                scalingMode: this.scalingMode,
                clampingMode: this.clampingMode,
                wallpaperDir: this.wallpaperDir,
                shuffleInterval: parseInt(this.shuffleInterval),
                maxFps: parseInt(this.maxFps)
            };
            global.log('Applying settings:', JSON.stringify(settings));
            const currentSettings = this._getCurrentSettings();
            Object.entries(settings).forEach(([setting, value]) => {
                if (value !== undefined && value !== currentSettings[setting]) {
                    if (setting === 'volumeLevel') {
                        value = Math.max(0, Math.min(100, parseInt(value) || 0));
                    } else if (setting === 'maxFps') {
                        value = Math.max(1, Math.min(240, parseInt(value) || 60));
                    } else if (setting === 'shuffleInterval') {
                        value = Math.max(1, Math.min(1440, parseInt(value) || 5));
                    }
                    this._runCommandAsync(
                        `${WALLPAPER_MANAGER_PATH} settings ${setting} ${value}`
                    );
                    global.log(`Updated ${setting} to ${value}`);
                }
            });
            this._updateStatus();
        } catch (e) {
            global.logError(`Failed to apply settings: ${e.message}`);
        }
    }
    _getCurrentSettings() {
        try {
            const settingsPath = `${GLib.get_home_dir()}/.cinnamon/configs/wallpaper-shuffle@abcdqfr/settings.json`;
            const [success, contents] = GLib.file_get_contents(settingsPath);
            if (!success) {
                global.logError("Failed to read current settings");
                return {};
            }
            const settings = JSON.parse(contents.toString());
            return {
                volumeLevel: settings.volumeLevel?.value,
                muteAudio: settings.muteAudio?.value,
                screenRoot: settings.screenRoot?.value,
                disableMouse: settings.disableMouse?.value,
                scalingMode: settings.scalingMode?.value,
                clampingMode: settings.clampingMode?.value,
                wallpaperDir: settings.wallpaperDir?.value
            };
        } catch (e) {
            global.logError('Failed to get current settings:', e.message);
            return {};
        }
    }
    _updateTooltip(extra = "") {
        const formatTime = (t) => `${String(Math.floor(t / 60)).padStart(2, "0")}:${String(t % 60).padStart(2, "0")}`;
        const status = this.timer
            ? `(${formatTime(this.remaining)} | ${formatTime(this.shuffleInterval * 60)})`
            : "Timer stopped";
        this.set_applet_tooltip(`${status} ${extra}`);
    }
    on_applet_clicked() {
        this.menu.toggle();
    }
    on_applet_about_clicked() {
        this._runCommandAsync(`xdg-open https://github.com/abcdqfr/wallpaper-shuffle`);
    }
    on_panel_height_changed() {
        this.set_applet_icon_symbolic_name("preferences-desktop-wallpaper");
    }
    on_applet_removed_from_panel() {
        this._stopTimer();
        if (this.settings) {
            this.settings.finalize();
        }
        this._runCommandAsync(`${WALLPAPER_MANAGER_PATH} exit`);
    }
    on_applet_config_changed() {
        global.log('Wallpaper Shuffle: Config changed called');
        this._on_settings_changed();
    }
    on_applet_about_to_be_clicked() {
        global.log('Wallpaper Shuffle: About to be clicked');
        this._run_command_async(`xdg-open https://github.com/abcdqfr/wallpaper-shuffle`);
    }
    _on_settings_changed() {
        global.log('Settings changed handler called');
        global.log(`Current shuffle interval: ${this.shuffleInterval}`);
        global.log(`Current volume level: ${this.volumeLevel}`);
        global.log(`Current screen: ${this.screenRoot}`);
        global.log(`Current scaling mode: ${this.scalingMode}`);
        global.log(`Current clamping mode: ${this.clampingMode}`);
        this._applySettings();
        this._updateTooltip();
    }
}
function main(metadata, orientation, panelHeight, instanceId) {
    return new WallpaperShuffleApplet(metadata, orientation, panelHeight, instanceId);
}
