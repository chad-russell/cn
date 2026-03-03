# vim: set ft=make :

[group('Appearance')]
set-icon-papirus:
    #!/usr/bin/env bash
    # Clean up static overrides to let GNOME/dconf take priority
    rm -f ~/.config/gtk-3.0/settings.ini ~/.config/gtk-4.0/settings.ini

    # Set icon theme
    gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'
    
    # Set matching cursor and dark mode preference
    gsettings set org.gnome.desktop.interface cursor-theme 'Adwaita'
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    
    echo "Icon theme set to Papirus-Dark and cleaned up legacy config files."

[group('Appearance')]
set-icon-adwaita:
    #!/usr/bin/env bash
    # Clean up static overrides
    rm -f ~/.config/gtk-3.0/settings.ini ~/.config/gtk-4.0/settings.ini

    # Reset to GNOME defaults
    gsettings set org.gnome.desktop.interface icon-theme 'Adwaita'
    gsettings set org.gnome.desktop.interface cursor-theme 'Adwaita'
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

    echo "Icon theme set to Adwaita (Default)."
