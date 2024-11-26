const Applet = imports.ui.applet;
const Util = imports.misc.util;
const Mainloop = imports.mainloop;
const Settings = imports.ui.settings;
const PopupMenu = imports.ui.popupMenu;
const WALLPAPER_MANAGER_PATH = `${__dirname}/wallpaper-manager.sh`;
class WallpaperShuffleApplet extends Applet.TextIconApplet {
    constructor(metadata, orientation, panelHeight, instanceId) {
        super(orientation, panelHeight, instanceId);
        this.settings = new Settings.AppletSettings(this, metadata.uuid, instanceId);
        ["shuffleInterval", "volume", "screen", "fps", "scaling", "window-geometry", "disable-mouse"].forEach(k => this.settings.bind(k, k, this._applySettings));
        this.set_applet_icon_name("preferences-desktop-wallpaper");
        this.set_applet_tooltip("Wallpaper Shuffle Controls");
        this.menuManager = new PopupMenu.PopupMenuManager(this);
        this.menu = new Applet.AppletPopupMenu(this, orientation);
        this.menuManager.addMenu(this.menu);
        this.menu.addMenuItem(new Applet.MenuItem("Toggle Timer", null, () => this._toggleTimer()));
        ["next", "prev", "shuffle", "exit"].forEach(cmd => this._addMenuItem(cmd));
        this.actor.connect("button-press-event", () => this.menu.toggle());
    }
    _addMenuItem(command) {
        this.menu.addMenuItem(new Applet.MenuItem(command.charAt(0).toUpperCase() + command.slice(1), null, () => Util.spawnCommandLine(`${WALLPAPER_MANAGER_PATH} ${command}`)));
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
                Util.spawnCommandLine(`${WALLPAPER_MANAGER_PATH} next`);
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
        command += `--volume ${this.volume} `;
        command += `--screen-root ${this.screen} `;
        command += `--fps ${this.fps} `;
        command += `--scaling ${this.scaling} `;
        command += `--window ${this.window_geometry} `;
        if (this.disableMouse) {
            command += `--disable-mouse `;
        }
        Util.spawnCommandLine(command);
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
