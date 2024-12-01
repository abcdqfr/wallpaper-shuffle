Wallpaper Shuffle

Wallpaper Shuffle is a Cinnamon applet designed for Linux Mint Cinnamon to enhance the functionality of the 
Linux Wallpaper Engine project by Almamu. It provides a graphical interface to control wallpaper shuffling 
settings. This applet allows users to automate wallpaper switching without needing to interact with the 
linux-wallpaperengine in the terminal, bringing back some basic functionality from wallpaper engine’s GUI.

    Note: This project is still in the alpha stage and is primarily a learning project. It’s an ongoing 
    effort to improve and add more features to streamline wallpaper management. EXPECT BUGS.

Features

    Wallpaper Shuffle: Randomizes wallpapers from a specified directory.
    Screen Selection: Choose the screen to display the wallpaper on (supports multi-monitor setups).
    Path Configuration: Specify paths to the linux-wallpaperengine executable and wallpaper directory 
    directly in the applet settings.

Installation

To install Wallpaper Shuffle, follow these steps:

    Clone the Repository: Open a terminal and navigate to the Cinnamon applets directory. 
    Then, clone the repository:

cd ~/.local/share/cinnamon/applets/

git clone https://github.com/abcdqfr/wallpaper-shuffle.git wallpaper-shuffle@abcdqfr


Restart Cinnamon: After cloning the repository, restart Cinnamon to load the applet. You can do this by:

    Right-clicking the taskbar, choosing Troubleshooting, and selecting Restart Cinnamon.
    Logging out and logging back in. 
    Run the following command in a terminal to restart Cinnamon: cinnamon --replace

Enable the Applet: Next open the Applets menu and enable Wallpaper Shuffle. 

Configure the Applet: The applet can be configured through the settings-schema.json file, 
which allows you to set the following options:

    linuxWPEPath: Path to the linux-wallpaperengine executable within the build directory.
    
    screen: Specify which screen to use for wallpaper display. See below example...
    
    wallpaperDir: Path to the folder containing your wallpaper engine library. 
    Should default to the standard Steam directory.

You can adjust these settings in the cinnamon applet config screen (click the gears), or 
directly in the settings-schema.json located at:

    ~/.local/share/cinnamon/applets/wallpaper-shuffle/settings-schema.json

Dependencies

    Linux Wallpaper Engine must be installed and properly configured.
    The applet requires jq to parse JSON settings.

Usage

Once the applet is installed and configured:

    Manage Wallpapers: The applet provides a blue icon in the taskbar. Clicking on this icon opens a 
    small popup window where you can manage wallpapers. The applet will automatically shuffle wallpapers 
    from the directory you've configured in the wallpaperDir option. You can trigger the shuffle manually 
    from the popup or set automatic shuffling intervals (if supported).

The applet will continuously use the wallpapers in the directory specified by the wallpaperDir option 
and will shuffle them based on your settings or preferences.

Development

This project is currently in alpha and is under development. We welcome contributions, bug reports, 
and suggestions for improvements. If you'd like to help out, feel free to fork the repository and 
submit pull requests!

To Contribute:

    Fork the repository.
    Create a feature branch (git checkout -b feature-branch).
    Commit your changes (git commit -m "Add feature").
    Push to your branch (git push origin feature-branch).
    Open a pull request.

License

This project is licensed under the MIT License - see the LICENSE file for details.

To Do

    ensure disable mouse functions in our script, functionality has already been ensured manually

    fix volume control
    update prev wallpaper whenever a new wallpaper is loaded

    "customWallpaperScale": {
        "type": "checkbox",
        "default": false,
        "description": "Use custom scaling for wallpapers",
        "tooltip": "Enable this to scale wallpapers according to your screen resolution."
    },
    "scalingOption": {
        "type": "radiogroup",
        "default": "fit",
        "description": "Wallpaper scaling option",
        "options": {
            "Fit": "fit",
            "Fill": "fill",
            "Stretch": "stretch"
        },
        "dependency": "customWallpaperScale",
        "tooltip": "Choose how wallpapers should be scaled to fit your screen."
    },
    "shuffleOrder": {
        "type": "radiogroup",
        "default": "random",
        "description": "Shuffle order",
        "options": {
            "Random": "random",
            "Sequential": "sequential"
        },
        "tooltip": "Choose whether the wallpapers should shuffle randomly or in sequential order."
    },
    "enableMultiMonitor": {
        "type": "checkbox",
        "default": false,
        "description": "Enable multi-monitor support",
        "tooltip": "Enable this to use different wallpapers on multiple monitors."
    },
    "useTransitionEffect": {
        "type": "checkbox",
        "default": true,
        "description": "Use transition effect when shuffling wallpapers",
        "tooltip": "Enable smooth transitions between wallpapers."
    },
    "transitionDuration": {
        "type": "spinbutton",
        "default": 2,
        "min": 1,
        "max": 10,
        "units": "seconds",
        "step": 1,
        "description": "Transition effect duration",
        "dependency": "useTransitionEffect",
        "tooltip": "Specify the duration (in seconds) of the transition effect between wallpapers."
    },
    "fadeEffect": {
        "type": "checkbox",
        "default": true,
        "description": "Use fade effect for wallpaper transition",
        "tooltip": "Enable this for a fade effect when changing wallpapers."
    },
    "scheduleShuffle": {
        "type": "checkbox",
        "default": false,
        "description": "Enable wallpaper shuffle on schedule",
        "tooltip": "Shuffle wallpapers only during specific hours or days."
    },
    "startTime": {
        "type": "entry",
        "default": "09:00",
        "description": "Start time for scheduled shuffle",
        "dependency": "scheduleShuffle",
        "tooltip": "Specify the time to start wallpaper shuffle (24-hour format, e.g., 09:00)."
    },
    "endTime": {
        "type": "entry",
        "default": "18:00",
        "description": "End time for scheduled shuffle",
        "dependency": "scheduleShuffle",
        "tooltip": "Specify the time to stop wallpaper shuffle (24-hour format, e.g., 18:00)."
    },
