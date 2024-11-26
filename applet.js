const { Gio } = imports.gi;
const Applet = imports.ui.applet;
const Mainloop = imports.mainloop;
const Settings = imports.ui.settings;
const PopupMenu = imports.ui.popupMenu;
const WALLPAPER_MANAGER_PATH = `${__dirname}/wallpaper-manager.sh`;
class WallpaperShuffleApplet extends Applet.TextIconApplet {
    constructor(metadata, orientation, panelHeight, instanceId) {
        super(orientation, panelHeight, instanceId);
        this.settings = new Settings.AppletSettings(this, metadata.uuid, instanceId);
        ["shuffleInterval", "volume", "screen", "fps", "scaling", "window-geometry", "disable-mouse"].forEach(k => this.settings.bind(k, k, this._applySettings));
        this.settings.bind("openHelpPage", null, this.openHelpPage.bind(this));
        this.set_applet_icon_name("preferences-desktop-wallpaper");
        this.set_applet_tooltip("Wallpaper Shuffle Controls");
        this.menuManager = new PopupMenu.PopupMenuManager(this);
        this.menu = new Applet.AppletPopupMenu(this, orientation);
        this.menuManager.addMenu(this.menu);
        this.menu.addMenuItem(new Applet.MenuItem("Toggle Timer", null, () => this._toggleTimer()));
        ["next", "prev", "shuffle", "exit"].forEach(cmd => this._addMenuItem(cmd));
        this.actor.connect("button-press-event", () => this.menu.toggle());
    }

    _runCommandAsync(command) {
        let proc = Gio.Subprocess.new(
            ['/bin/bash', '-c', command],
            Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE
        );
        proc.communicate_async(null, null, (proc, res) => {
            try {
                let [ok, stdout, stderr] = proc.communicate_finish(res);
                if (ok) {
                    global.log(`Command output: ${stdout.toString().trim()}`);
                } else {
                    global.logError(`Command error: ${stderr.toString().trim()}`);
                }
            } catch (err) {
                global.logError(`Command failed: ${err}`);
            }
        });
    }
    _addMenuItem(command) {
        this.menu.addMenuItem(new Applet.MenuItem(command.charAt(0).toUpperCase() + command.slice(1), null, () => this._runCommandAsync(`${WALLPAPER_MANAGER_PATH} ${command}`)));
    }
/* 
    _updateStatus() {
        const schemaPath = `${GLib.get_home_dir()}/.local/share/cinnamon/applets/wallpaper-shuffle/settings-schema.json`;
        try {
            const settings = JSON.parse(Cinnamon.get_file_contents_utf8_sync(schemaPath));
            this.settings.setValue("currentWallpaper", settings.currentWallpaper.default || "Unknown");
            this.settings.setValue("previousWallpaper", settings.previousWallpaper.default || "None");
            this.settings.setValue("queueLength", settings.queueLength.default.toString() || "0");
            this.settings.setValue("currentIndex", settings.currentIndex.default.toString() || "0");
            this.settings.setValue("shuffleStatus", settings.shuffleStatus.default || "Stopped");
        } catch (e) {
            global.logError("Failed to read or parse status from settings-schema.json: " + e);
        }
    }
    
    Mainloop.timeout_add_seconds(5, () => {
        this._updateStatus();
        return true;
    });

    _readFile(filePath, defaultValue) {
        try {
            const fileContent = Cinnamon.get_file_contents_utf8_sync(filePath);
            return fileContent ? fileContent.trim() : defaultValue;
        } catch (e) {
            return defaultValue;
        }
    }

    _getQueueLength() {
        try {
            const queue = Cinnamon.get_file_contents_utf8_sync("/tmp/wallpaper_queue").split("\n");
            return queue.filter(line => line.trim()).length;
        } catch (e) {
            return 0;
        }
    } */
    _toggleTimer() {
        this.timer ? this._stopTimer() : this._startTimer();
    }
    _startTimer() {
        this.remaining = this.shuffleInterval * 60;
        this.timer = Mainloop.timeout_add_seconds(1, () => {
            if (this.remaining > 0) {
                this.remaining--;
                this._updateTooltip();
            } else {
                this._runCommandAsync(`${WALLPAPER_MANAGER_PATH} next`);
                this.remaining = this.shuffleInterval * 60;
                this._updateTooltip("Timer reset");
            }
            return true;
        });
        this._updateTooltip("Timer started");
    }
    _stopTimer() {
        if (this.timer) {
            Mainloop.source_remove(this.timer);
            this.timer = null;
        }
        this._updateTooltip("Timer stopped");
    }
    openHelpPage() {
        this._runCommandAsync(`xdg-open ${"https://github.com/abcdqfr/wallpaper-shuffle"}`);
    }
    _applySettings() {
        let command = `${WALLPAPER_MANAGER_PATH} `;
        command += `--volume ${this.volume} `;
        command += `--screen-root ${this.screen} `;
        command += `--fps ${this.fps} `;
        command += `--scaling ${this.scaling} `;
        command += `--window ${this.window_geometry} `;
        if (this.disableMouse) {
            command += `--disable-mouse `;
        }
        this._runCommandAsync(command);
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
    on_panel_height_changed() {
        this.set_applet_icon_symbolic_name("preferences-desktop-wallpaper");
    }
}
function main(metadata, orientation, panelHeight, instanceId) {
    return new WallpaperShuffleApplet(metadata, orientation, panelHeight, instanceId);
}
