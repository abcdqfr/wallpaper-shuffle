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
        ["shuffle-interval", "volume-level", "screen", "linux-wpe-path", "wallpaper-dir", "disable-mouse"].forEach(k => this.settings.bind(k, k, this._applySettings));
        this.set_applet_icon_name("preferences-desktop-wallpaper");
        this.set_applet_tooltip("Wallpaper Shuffle Controls");
        this.menuManager = new PopupMenu.PopupMenuManager(this);
        this.menu = new Applet.AppletPopupMenu(this, orientation);
        this.menuManager.addMenu(this.menu);
        this.menu.addMenuItem(new Applet.MenuItem("Toggle Timer", null, () => this._toggleTimer()));
        ["queue", "next", "prev", "exit"].forEach(cmd => this._addMenuItem(cmd));
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
    _updateStatus() {
        const schemaPath = `${GLib.get_home_dir()}/.local/share/cinnamon/applets/wallpaper-shuffle/settings-schema.json`;
        const file = Gio.file_new_for_path(schemaPath);
        
        file.load_contents_async(null, (aFile, aResponse) => {
            let success, contents, tag;

            try {
                [success, contents, tag] = aFile.load_contents_finish(aResponse);
            } catch (err) {
                global.logError("Failed to read settings-schema.json: " + err.message);
                return;
            }

            if (!success) {
                global.logError("Error reading settings-schema.json");
                return;
            }

            try {
                const settings = JSON.parse(contents.toString());
                this.settings.setValue("current-wallpaper", settings["current-wallpaper"].default || "Unknown");
                this.settings.setValue("previous-wallpaper", settings["previous-wallpaper"].default || "None");
                this.settings.setValue("queue-length", settings["queue-length"].default.toString() || "0");
                this.settings.setValue("current-index", settings["current-index"].default.toString() || "0");
                this.settings.setValue("shuffle-status", settings["shuffle-status"].default || "Stopped");
            } catch (err) {
                global.logError("Failed to parse settings-schema.json: " + err.message);
            }
        });
    }
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
    _applySettings() {
        let command = `${WALLPAPER_MANAGER_PATH} `;
        command += `--volume ${this.volumeLevel} `;
        command += `--screen-root ${this.screen} `;
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
    on_applet_about_clicked() {
        this._runCommandAsync(`xdg-open https://github.com/abcdqfr/wallpaper-shuffle`);
    }
    on_panel_height_changed() {
        this.set_applet_icon_symbolic_name("preferences-desktop-wallpaper");
    }
}
function main(metadata, orientation, panelHeight, instanceId) {
    return new WallpaperShuffleApplet(metadata, orientation, panelHeight, instanceId);
}
