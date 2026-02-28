{ config, pkgs, lib, ... }:

{
  # Create mango config directory and files
  xdg.configFile."mango/config.conf".text = ''
    # MangoWC Configuration
    # See: https://mangowc.com/docs/configuration/basics

    # Import additional configs
    source=${config.xdg.configHome}/mango/monitors.conf
    source=${config.xdg.configHome}/mango/binds.conf
    source=${config.xdg.configHome}/mango/appearance.conf
    source=${config.xdg.configHome}/mango/autostart.conf

    # Environment Variables
    env=GTK_THEME,Adwaita:dark
    env=XCURSOR_THEME,Bibata-Modern-Classic
    env=XCURSOR_SIZE,18
    env=GTK_CURSOR_THEME_NAME,Bibata-Modern-Classic

    # General settings
    general {
        gaps_in=8
        gaps_out=8
        border_size=2
        col.active_border=rgba(88c0d0ff)
        col.inactive_border=rgba(3b4252ff)
    }
    
    # Overview settings
    overviewgappi=5
    overviewgappo=30

    # Input configuration
    # Keyboard
    kb_layout=us
    xkb_rules_options=caps:swapescape
    numlock_by_default=true
    
    # Touchpad
    trackpad_natural_scrolling=1
    tap_to_click=1
    tap_and_drag=1
    swipe_min_threshold=1
    
    # Mouse
    mouse_natural_scrolling=1

    # Monitor configuration (will be overridden by specific monitor setup)
    monitor=,preferred,auto,1
  '';

  xdg.configFile."mango/binds.conf".text = ''
    # Key Bindings for MangoWC
    
    # Applications
    bind=SUPER,Return,spawn,wezterm
    bind=SUPER,T,spawn,wezterm
    bind=SUPER,space,spawn_shell,${pkgs.vicinae}/bin/vicinae toggle
    bind=SUPER,B,spawn_shell,flatpak run app.zen_browser.zen
    bind=SUPER,F,spawn_shell,nautilus --new-window
    bind=NONE,F10,spawn,pavucontrol

    # Window Management
    bind=SUPER,Q,killclient
    bind=SUPER,V,togglefloating
    bind=SUPER+SHIFT,F,togglefullscreen
    bind=SUPER,X,togglemaximizescreen
    bind=SUPER,C,centerwin

    # Focus Movement (Vim-style + Arrow keys)
    bind=SUPER,Left,focusdir,left
    bind=SUPER,Down,focusdir,down
    bind=SUPER,Up,focusdir,up
    bind=SUPER,Right,focusdir,right
    bind=SUPER,H,focusdir,left
    bind=SUPER,J,focusdir,down
    bind=SUPER,K,focusdir,up
    bind=SUPER,L,focusdir,right

    # Window Movement
    bind=SUPER+CTRL,Left,exchange_client,left
    bind=SUPER+CTRL,Down,exchange_client,down
    bind=SUPER+CTRL,Up,exchange_client,up
    bind=SUPER+CTRL,Right,exchange_client,right
    bind=SUPER+CTRL,H,exchange_client,left
    bind=SUPER+CTRL,J,exchange_client,down
    bind=SUPER+CTRL,K,exchange_client,up
    bind=SUPER+CTRL,L,exchange_client,right

    # Tag Navigation (Workspaces)
    bind=CTRL,1,view,1
    bind=CTRL,2,view,2
    bind=CTRL,3,view,3
    bind=CTRL,4,view,4
    bind=CTRL,5,view,5
    bind=CTRL,6,view,6
    bind=CTRL,7,view,7
    bind=CTRL,8,view,8
    bind=CTRL,9,view,9

    # Move Window to Tag
    bind=ALT,1,tag,1
    bind=ALT,2,tag,2
    bind=ALT,3,tag,3
    bind=ALT,4,tag,4
    bind=ALT,5,tag,5
    bind=ALT,6,tag,6
    bind=ALT,7,tag,7
    bind=ALT,8,tag,8
    bind=ALT,9,tag,9

    # Layout Management
    bind=SUPER,O,toggleoverview
    bind=SUPER,minus,setmfact,-0.05
    bind=SUPER,equal,setmfact,+0.05
    bind=SUPER+SHIFT,minus,incnmaster,-1
    bind=SUPER+SHIFT,equal,incnmaster,+1
    bind=SUPER,tab,switch_layout

    # Gaps
    bind=SUPER+SHIFT,g,togglegaps

    # Scratchpad

    bind=SUPER,S,toggle_scratchpad

    # DankMaterialShell Bindings
    bind=SUPER,n,spawn_shell,dms ipc notifications toggle
    bind=SUPER,comma,spawn_shell,dms ipc settings toggle
    bind=SUPER,m,spawn_shell,dms ipc processlist toggle
    bind=SUPER+ALT,n,spawn_shell,dms ipc night toggle
    bind=SUPER,e,spawn_shell,dms ipc powermenu toggle
    bind=SUPER+SHIFT,b,spawn_shell,dms ipc bar toggle
    bindl=SUPER+ALT,l,spawn_shell,dms ipc lock lock

    # Media Keys (using DMS)
    bindl=NONE,XF86AudioRaiseVolume,spawn_shell,dms ipc audio increment 3
    bindl=NONE,XF86AudioLowerVolume,spawn_shell,dms ipc audio decrement 3
    bindl=NONE,XF86AudioMute,spawn_shell,dms ipc audio mute
    bindl=NONE,XF86AudioMicMute,spawn_shell,dms ipc audio micmute
    bindl=NONE,XF86MonBrightnessUp,spawn_shell,dms ipc brightness increment 5
    bindl=NONE,XF86MonBrightnessDown,spawn_shell,dms ipc brightness decrement 5

    # System
    bind=SUPER,p,spawn_shell,grim -g "$(slurp)" - | wl-copy
    bind=SUPER,r,reload_config
    bind=SUPER+SHIFT,e,quit
    bind=CTRL+ALT,delete,spawn_shell,dms ipc processlist toggle

    # Touchpad Gestures (3-finger swipe to move focus)
    gesturebind=none,left,3,focusdir,right
    gesturebind=none,right,3,focusdir,left
    gesturebind=none,up,3,focusdir,down
    gesturebind=none,down,3,focusdir,up
  '';

  xdg.configFile."mango/appearance.conf".text = ''
    # Appearance Configuration
    
    decoration {
        rounding=12
        
        blur {
            enabled=true
            size=8
            passes=2
        }
        
        border_radius=13
        
        drop_shadow=true
        shadow_range=20
        shadow_render_power=3
        col.shadow=rgba(1a1a1aee)
    }

    animations {
        enabled=true
        
        animation=windows,1,5,default
        animation=windowsOut,1,5,default,popin 80%
        animation=border,1,10,default
        animation=fade,1,5,default
        animation=workspaces,1,5,default
    }
  '';

  xdg.configFile."mango/monitors.conf".text = ''
    # Monitor Configuration
    # Laptop Screen (AU Optronics) - Scaled at 1.25 for better readability
    monitor=eDP-1,1920x1200@60,0x0,1.25

    # First Dell Monitor
    monitor=DP-3,1920x1080@60,1536x0,1.0

    # Second Dell Monitor  
    monitor=DP-4,1920x1080@60,0x0,1.0
  '';

  xdg.configFile."mango/autostart.conf".text = ''
    # Autostart Applications
    
    # DankMaterialShell (systemd service will handle this, but keep as fallback)
    # exec-once=dms
    
    # XWayland satellite for X11 app compatibility
    exec-once=${pkgs.xwayland-satellite}/bin/xwayland-satellite
    
    # Notification daemon (if not using DMS notifications)
    # exec-once=mako
    
    # Clipboard manager
    exec-once=wl-paste --watch cliphist store
  '';

  # Install required packages
  home.packages = with pkgs; [
    grim          # Screenshot tool
    slurp         # Region selector
    cliphist      # Clipboard history
  ];
}

