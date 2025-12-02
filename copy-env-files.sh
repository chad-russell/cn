#!/usr/bin/env bash

# Define machines and their IPs
declare -A MACHINES
MACHINES["k2"]="192.168.20.62"
MACHINES["k3"]="192.168.20.63"
MACHINES["k4"]="192.168.20.64"

USER="crussell"
BASE_REMOTE_DIR="/home/crussell/cn"

# Loop through each machine
for MACHINE in "${!MACHINES[@]}"; do
    IP="${MACHINES[$MACHINE]}"
    SOURCE_DIR="$MACHINE/docker"
    
    echo "--------------------------------------------------"
    echo "Processing $MACHINE ($IP)..."
    
    if [ ! -d "$SOURCE_DIR" ]; then
        echo "Warning: Local directory $SOURCE_DIR does not exist. Skipping."
        continue
    fi

    # Target directory on remote
    REMOTE_TARGET="$USER@$IP:$BASE_REMOTE_DIR/$MACHINE/docker/"

    echo "Copying .env files from $SOURCE_DIR to $REMOTE_TARGET"

    # Ensure remote directory exists
    ssh "$USER@$IP" "mkdir -p $BASE_REMOTE_DIR/$MACHINE/docker/"

    # Find and copy all .env files using scp
    # We first find them locally, then copy each one to preserve structure relative to SOURCE_DIR
    find "$SOURCE_DIR" -name "*.env" | while read -r FILE; do
        # Get relative path of the file (e.g., "karakeep/.env")
        REL_PATH="${FILE#$SOURCE_DIR/}"
        # Remote destination file path
        REMOTE_FILE="$BASE_REMOTE_DIR/$MACHINE/docker/$REL_PATH"
        # Remote destination directory
        REMOTE_DIR=$(dirname "$REMOTE_FILE")
        
        echo "  $REL_PATH -> $REMOTE_FILE"
        
        # Create remote directory if needed
        ssh -n "$USER@$IP" "mkdir -p \"$REMOTE_DIR\""
        
        # Copy file
        scp -p "$FILE" "$USER@$IP:$REMOTE_FILE"
    done
done

echo "--------------------------------------------------"
echo "Done."

