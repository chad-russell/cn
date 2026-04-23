# Custom functions

# Create directory and change to it
function mkcd {
  mkdir -p $1;
  cd $1;
}

# Kill process listening on a port
function killport {
  lsof -ti:$1 | xargs kill -9
}

function cjust_swap_caps_escape_gnome {
    gsettings set org.gnome.desktop.input-sources xkb-options "['caps:swapescape']"
}
