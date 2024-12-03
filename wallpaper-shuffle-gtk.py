#!/usr/bin/env python3
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, GdkPixbuf, GLib, Gio, Gdk
import json, os, subprocess, threading, signal, logging, time
from pathlib import Path

class ScriptRunner:
    def __init__(self, script_path):
        self.script = script_path
        self.log = logging.getLogger('ScriptRunner')
    
    def run(self, *args, parent_window=None):
        """Run command with proper GTK feedback"""
        spinner = None
        try:
            cmd = [self.script] + list(args)
            cmd_str = ' '.join(str(arg) for arg in cmd)
            self.log.debug(f"Running command: {cmd_str}")
            
            if parent_window:
                # Show operation in progress using status label instead
                if hasattr(parent_window, 'status_label'):
                    original_text = parent_window.status_label.get_text()
                    parent_window.status_label.set_text("Working...")
                parent_window.set_sensitive(False)
                
                # Process GTK events
                while Gtk.events_pending():
                    Gtk.main_iteration()
            
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode != 0:
                if parent_window:
                    self.log.error(f"Script error: {result.stderr}")
                    parent_window.status_label.set_text(f"Error: {result.stderr}")
            
            return result
            
        except Exception as e:
            self.log.error(f"Failed to run script: {e}")
            if parent_window and hasattr(parent_window, 'status_label'):
                parent_window.status_label.set_text(f"Error: {str(e)}")
            return None
            
        finally:
            if parent_window:
                parent_window.set_sensitive(True)
                # Restore original status if there was no error
                if hasattr(parent_window, 'status_label') and result and result.returncode == 0:
                    parent_window.status_label.set_text(original_text)
    
    def run_async(self, *args, callback=None):
        """Async run only for operations that truly need it"""
        thread = threading.Thread(target=lambda: callback(self.run(*args)) if callback else self.run(*args))
        thread.daemon = True
        thread.start()

class WidgetFactory:
    @staticmethod
    def create_switch(label, tooltip="", active=False):
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        box.pack_start(Gtk.Label(label=label), False, False, 0)
        switch = Gtk.Switch()
        switch.set_active(active)
        switch.set_tooltip_text(tooltip)
        box.pack_end(switch, False, False, 0)
        return box, switch
    
    @staticmethod
    def create_scale(label, min_val, max_val, step, tooltip="", value=None):
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        box.pack_start(Gtk.Label(label=label), False, False, 0)
        scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, min_val, max_val, step)
        if value is not None:
            scale.set_value(float(value))
        scale.set_tooltip_text(tooltip)
        box.pack_start(scale, True, True, 0)
        return box, scale
    
    @staticmethod
    def create_combo(label, options, tooltip="", active=None):
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        box.pack_start(Gtk.Label(label=label), False, False, 0)
        combo = Gtk.ComboBoxText()
        for opt in options:
            combo.append_text(opt)
        if active is not None:
            combo.set_active(active)
        combo.set_tooltip_text(tooltip)
        box.pack_start(combo, True, True, 0)
        return box, combo

class SettingsDialog(Gtk.Dialog):
    def __init__(self, parent):
        super().__init__(title="Wallpaper Shuffle Settings", parent=parent, flags=0)
        self.settings = parent.settings
        self.script_runner = parent.script_runner
        self.set_default_size(400, 600)
        
        box = self.get_content_area()
        box.set_spacing(6)
        box.set_margin_top(12)
        box.set_margin_bottom(12)
        box.set_margin_start(12)
        box.set_margin_end(12)
        
        notebook = Gtk.Notebook()
        box.pack_start(notebook, True, True, 0)
        
        pages = {
            "Basic": self._create_basic_page(),
            "Audio": self._create_audio_page(),
            "Display": self._create_display_page(),
            "Performance": self._create_performance_page()
        }
        
        for label, page in pages.items():
            notebook.append_page(page, Gtk.Label(label=label))
        
        self.add_button("Close", Gtk.ResponseType.CLOSE)
        self.show_all()
        self.connect("response", self.on_response)
    
    def _create_basic_page(self):
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        
        for setting, label in [("linuxWpePath", "Linux WPE Path"), ("wallpaperDir", "Wallpaper Directory")]:
            chooser = Gtk.FileChooserButton(title=f"Select {label}")
            chooser.set_action(Gtk.FileChooserAction.SELECT_FOLDER)
            current_path = os.path.expanduser(self.settings.get(setting, {}).get("value", ""))
            if current_path:
                chooser.set_filename(current_path)
            chooser.set_tooltip_text(self.settings.get(setting, {}).get("tooltip", ""))
            chooser.connect("file-set", self.on_path_changed, setting)
            
            box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
            box.pack_start(Gtk.Label(label=label), False, False, 0)
            box.pack_start(chooser, True, True, 0)
            page.pack_start(box, False, False, 0)
        
        return page
    
    def _create_audio_page(self):
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        
        # Volume scale
        value = self.settings.get("volumeLevel", {}).get("value", 50)
        box, scale = WidgetFactory.create_scale("Volume Level:", 0, 100, 1, 
            self.settings.get("volumeLevel", {}).get("tooltip", ""),
            value=value)
        scale.connect("value-changed", self.on_value_changed, "volumeLevel")
        page.pack_start(box, False, False, 0)
        
        # Audio switches
        switches = [
            ("Mute Audio", "muteAudio"),
            ("Disable Auto-mute", "noAutomute"),
            ("Disable Audio Processing", "noAudioProcessing")
        ]
        
        for label, setting in switches:
            active = self.settings.get(setting, {}).get("value", False)
            box, switch = WidgetFactory.create_switch(label, 
                self.settings.get(setting, {}).get("tooltip", ""),
                active=active)
            switch.connect("notify::active", self.on_switch_toggled, setting)
            page.pack_start(box, False, False, 0)
        
        return page
    
    def _create_display_page(self):
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        
        # Screen output
        current_screen = self.settings.get("screenRoot", {}).get("value", "")
        box, entry = WidgetFactory.create_combo("Screen Output:", 
            [current_screen] if current_screen else ["Default"],
            self.settings.get("screenRoot", {}).get("tooltip", ""))
        entry.connect("changed", self.on_text_changed, "screenRoot")
        page.pack_start(box, False, False, 0)
        
        # Scaling mode
        modes = ["Default", "Stretch", "Fit", "Fill"]
        current_mode = self.settings.get("scalingMode", {}).get("value", "default")
        active = modes.index(current_mode.capitalize()) if current_mode else 0
        box, combo = WidgetFactory.create_combo("Scaling Mode:", modes,
            self.settings.get("scalingMode", {}).get("tooltip", ""),
            active=active)
        combo.connect("changed", self.on_combo_changed, "scalingMode")
        page.pack_start(box, False, False, 0)
        
        return page
    
    def _create_performance_page(self):
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        
        # FPS limit
        value = self.settings.get("maxFps", {}).get("value", 60)
        box, scale = WidgetFactory.create_scale("Maximum FPS:", 1, 240, 1,
            self.settings.get("maxFps", {}).get("tooltip", ""),
            value=value)
        scale.connect("value-changed", self.on_value_changed, "maxFps")
        page.pack_start(box, False, False, 0)
        
        # Performance switches
        switches = [
            ("Disable Fullscreen Pause", "noFullscreenPause"),
            ("Disable Mouse", "disableMouse")
        ]
        
        for label, setting in switches:
            active = self.settings.get(setting, {}).get("value", False)
            box, switch = WidgetFactory.create_switch(label,
                self.settings.get(setting, {}).get("tooltip", ""),
                active=active)
            switch.connect("notify::active", self.on_switch_toggled, setting)
            page.pack_start(box, False, False, 0)
        
        return page
    
    def on_path_changed(self, chooser, setting):
        path = chooser.get_filename()
        if path:
            subprocess.run([self.script_runner.script, "settings", setting, path])
            if setting == "wallpaperDir":
                self.get_parent().flowbox.foreach(lambda w: w.destroy())
                self.get_parent().load_wallpapers()
    
    def on_value_changed(self, widget, setting):
        value = widget.get_value()
        subprocess.run([self.script_runner.script, "settings", setting, str(int(value))])
    
    def on_switch_toggled(self, switch, gparam, setting):
        value = "true" if switch.get_active() else "false"
        subprocess.run([self.script_runner.script, "settings", setting, value])
    
    def on_text_changed(self, entry, setting):
        value = entry.get_active_text()
        if value:
            subprocess.run([self.script_runner.script, "settings", setting, value])
    
    def on_combo_changed(self, combo, setting):
        value = combo.get_active_text().lower()
        subprocess.run([self.script_runner.script, "settings", setting, value])
    
    def on_response(self, dialog, response_id):
        if response_id == Gtk.ResponseType.CLOSE:
            self.destroy()

class WallpaperShuffleWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title="Wallpaper Shuffle")
        self.set_default_size(800, 600)
        
        # Initialize logger
        self.log = logging.getLogger('Window')
        logging.basicConfig(
            level=logging.DEBUG,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
        
        script_path = os.path.expanduser("~/.local/share/cinnamon/applets/wallpaper-shuffle@abcdqfr/wallpaper-manager.sh")
        self.script_runner = ScriptRunner(script_path)
        
        # Load settings
        self.settings_file = Path.home() / ".local/share/cinnamon/applets/wallpaper-shuffle@abcdqfr/settings-schema.json"
        self.load_settings()
        
        self.main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.add(self.main_box)
        
        self._create_toolbar()
        self._create_flowbox()
        self.create_tray_icon()
        self.load_wallpapers()
        
        self.connect("delete-event", self.on_window_delete)
        # Register cleanup on window destroy
        self.connect("destroy", self.on_destroy)
    
    def load_settings(self):
        try:
            with open(self.settings_file) as f:
                self.settings = json.load(f)
        except (FileNotFoundError, json.JSONDecodeError):
            self.settings = {}
    
    def _create_toolbar(self):
        toolbar = Gtk.Toolbar()
        toolbar.get_style_context().add_class(Gtk.STYLE_CLASS_PRIMARY_TOOLBAR)
        self.main_box.pack_start(toolbar, False, False, 0)
        
        # Add status label
        self.status_label = Gtk.Label(label="Current: None")
        toolbar.insert(Gtk.SeparatorToolItem(), -1)  # Add separator
        item = Gtk.ToolItem()
        item.add(self.status_label)
        toolbar.insert(item, -1)
        
        buttons = [
            ("media-skip-backward-symbolic", "Previous", self.on_prev_clicked),
            ("media-skip-forward-symbolic", "Next", self.on_next_clicked),
            ("media-playlist-shuffle-symbolic", "Random", self.on_random_clicked),
            ("preferences-system-symbolic", "Settings", self.on_settings_clicked)
        ]
        
        for icon, tooltip, callback in buttons:
            button = Gtk.ToolButton()
            button.set_icon_name(icon)
            button.set_tooltip_text(tooltip)
            button.connect("clicked", callback)
            toolbar.insert(button, -1)
    
    def _create_flowbox(self):
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.main_box.pack_start(scrolled, True, True, 0)
        
        self.flowbox = Gtk.FlowBox()
        self.flowbox.set_valign(Gtk.Align.START)
        self.flowbox.set_max_children_per_line(30)
        self.flowbox.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.flowbox.connect("child-activated", self.on_wallpaper_selected)
        
        scrolled.add(self.flowbox)
    
    def create_tray_icon(self):
        self.tray_icon = Gtk.StatusIcon()
        self.tray_icon.set_from_icon_name("preferences-desktop-wallpaper")
        self.tray_icon.set_tooltip_text("Wallpaper Shuffle")
        self.tray_icon.connect("popup-menu", self.on_tray_right_click)
        self.tray_icon.connect("activate", self.on_tray_left_click)
        
        self.tray_menu = Gtk.Menu()
        menu_items = [
            ("Next", self.on_next_clicked),
            ("Previous", self.on_prev_clicked),
            ("Random", self.on_random_clicked),
            (None, None),
            ("Show Window", self.show_window),
            (None, None),
            ("Exit", self.on_exit_clicked)
        ]
        
        for label, callback in menu_items:
            if label is None:
                item = Gtk.SeparatorMenuItem()
            else:
                item = Gtk.MenuItem(label=label)
                item.connect("activate", callback)
            self.tray_menu.append(item)
        
        self.tray_menu.show_all()
    
    def load_wallpapers(self):
        def load_previews():
            wallpaper_dir = os.path.expanduser(self.settings.get("wallpaperDir", {}).get("value", ""))
            self.log.info(f"Loading previews from: {wallpaper_dir}")
            
            if not wallpaper_dir:
                self.log.error("No wallpaper directory configured")
                return
            
            try:
                wallpapers = os.listdir(wallpaper_dir)
                self.log.info(f"Found {len(wallpapers)} potential wallpaper directories")
                
                for wallpaper_id in wallpapers:
                    path = os.path.join(wallpaper_dir, wallpaper_id)
                    if os.path.isdir(path):
                        self.log.debug(f"Scanning directory: {wallpaper_id}")
                        preview_file = next((f for f in os.listdir(path) 
                                           if f.startswith("preview.") and 
                                           f.endswith((".jpg", ".png", ".gif"))), None)
                        if preview_file:
                            preview_path = os.path.join(path, preview_file)
                            self.log.debug(f"Found preview for {wallpaper_id}: {preview_file}")
                            GLib.idle_add(lambda p=preview_path, w=wallpaper_id: 
                                self.add_wallpaper_preview(p, w))
                        else:
                            self.log.warning(f"No valid preview found for {wallpaper_id}")
                            
            except Exception as e:
                self.log.error(f"Failed to load wallpapers: {e}", exc_info=True)
        
        thread = threading.Thread(target=load_previews)
        thread.daemon = True
        thread.start()
    
    def add_wallpaper_preview(self, preview_path, wallpaper_id):
        try:
            # Only load first frame of GIFs
            if preview_path.lower().endswith('.gif'):
                pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_size(
                    preview_path, 
                    200, 200
                )
                # Force load only first frame
                pixbuf = pixbuf.get_static_image()
            else:
                pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(
                    preview_path, 
                    200, 200, 
                    True
                )
            
            image = Gtk.Image.new_from_pixbuf(pixbuf)
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
            box.pack_start(image, True, True, 0)
            
            label = Gtk.Label(label=wallpaper_id)
            box.pack_start(label, False, False, 0)
            
            box.wallpaper_id = wallpaper_id
            self.flowbox.add(box)
            box.show_all()  # Ensure widget is visible
            
        except Exception as e:
            print(f"Error loading preview for {wallpaper_id}: {e}")
    
    def on_wallpaper_selected(self, flowbox, child):
        wallpaper_id = child.get_child().wallpaper_id
        self.log.info(f"Loading wallpaper: {wallpaper_id}")
        
        # Direct synchronous call - no callback needed
        result = self.script_runner.run("load", wallpaper_id)
        
        if result and result.returncode == 0:
            self.log.debug(f"Load succeeded for {wallpaper_id}")
            self.status_label.set_text(f"Current: {wallpaper_id}")
        else:
            self.log.error(f"Failed to load {wallpaper_id}")
    
    def on_prev_clicked(self, button):
        result = self.script_runner.run("prev")
        if result and result.returncode == 0:
            self.log.debug("Previous wallpaper loaded successfully")
    
    def on_next_clicked(self, button):
        result = self.script_runner.run("next")
        if result and result.returncode == 0:
            self.log.debug("Next wallpaper loaded successfully")
    
    def on_random_clicked(self, button):
        self.script_runner.run_async("random")
    
    def on_settings_clicked(self, button):
        dialog = SettingsDialog(self)
        dialog.run()
        dialog.destroy()
    
    def on_exit_clicked(self, button):
        # First hide the window to give user feedback
        self.hide()
        
        def after_exit(result):
            # Use GLib.idle_add to safely quit from main thread
            GLib.idle_add(Gtk.main_quit)
        
        # Kill wallpaper engine asynchronously
        self.script_runner.run_async("exit", callback=after_exit)
    
    def on_tray_right_click(self, icon, button, time):
        self.tray_menu.popup(None, None, None, None, button, time)
    
    def on_tray_left_click(self, icon):
        self.show_window()
    
    def show_window(self, *args):
        self.present()
        self.deiconify()
        self.set_keep_above(True)
        GLib.timeout_add(100, lambda: self.set_keep_above(False))
    
    def on_window_delete(self, window, event):
        # Handle window close button
        if self.tray_icon.get_visible():
            self.hide()
            return True  # Prevent destruction
        else:
            # No tray icon, perform clean exit
            self.on_exit_clicked(None)
            return True  # Prevent immediate destruction
    
    def run_script(self, *args):
        try:
            result = subprocess.run([self.script_runner.script] + list(args), 
                                  capture_output=True, 
                                  text=True)
            if result.returncode != 0:
                print(f"Script error: {result.stderr}")
            return result
        except Exception as e:
            print(f"Failed to run script: {e}")
            return None
    
    def on_destroy(self, window):
        self.script_runner.cleanup()
        Gtk.main_quit()

def main():
    win = WallpaperShuffleWindow()
    win.connect("destroy", Gtk.main_quit)
    win.show_all()
    Gtk.main()

if __name__ == "__main__":
    main()
