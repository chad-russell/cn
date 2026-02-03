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

# Show what's listening on a port
function whichport {
  lsof -i :$1
}
