#!/bin/bash

# Source environment variables
source $HOME/.bash_profile 2>/dev/null

# Set defaults for service names
OG_SERVICE_NAME=${OG_SERVICE_NAME:-0gchaind}
OG_GETH_SERVICE_NAME=${OG_GETH_SERVICE_NAME:-0g-geth}

function update_version {
    VERSION=$1
    RELEASE_URL="$2/aristotle-${VERSION}.tar.gz"
    BACKUP_DIR="$HOME/backups"
 
    echo "Updating to version $VERSION..."
    
    # Stop services
    sudo systemctl stop ${OG_GETH_SERVICE_NAME} || { echo "Failed to stop ${OG_GETH_SERVICE_NAME}"; exit 1; }
    sudo systemctl stop ${OG_SERVICE_NAME} || { echo "Failed to stop ${OG_SERVICE_NAME}"; exit 1; }
 
    # Backup old binaries
    TIMESTAMP=$(date +%Y%m%d%H%M%S)
    mkdir -p $BACKUP_DIR
    [ -f $HOME/go/bin/0g-geth ] && cp $HOME/go/bin/0g-geth $BACKUP_DIR/0g-geth.$TIMESTAMP
    [ -f $HOME/go/bin/0gchaind ] && cp $HOME/go/bin/0gchaind $BACKUP_DIR/0gchaind.$TIMESTAMP
 
    # Download and install new version
    cd $HOME
    wget $RELEASE_URL || { echo "Download failed"; exit 1; }
    tar -xzf aristotle-${VERSION}.tar.gz || { echo "Extraction failed"; exit 1; }
    rm aristotle-${VERSION}.tar.gz

    cp aristotle-${VERSION}/bin/geth $HOME/go/bin/0g-geth
    cp aristotle-${VERSION}/bin/0gchaind $HOME/go/bin/0gchaind
    sudo chmod +x $HOME/go/bin/0g-geth
    sudo chmod +x $HOME/go/bin/0gchaind


    # Restart services
    sudo systemctl daemon-reload
    sudo systemctl start ${OG_GETH_SERVICE_NAME} || { echo "Failed to start ${OG_GETH_SERVICE_NAME}"; exit 1; }
    sudo systemctl start ${OG_SERVICE_NAME} || { echo "Failed to start ${OG_SERVICE_NAME}"; exit 1; }

    echo "Update to 0gchain-Aristotle $VERSION completed!"
}

BASE_URL="https://github.com/0gfoundation/0gchain-Aristotle/releases/download"

# Display menu
echo "Select version to update:"
echo "a) v1.0.2"
echo "b) v1.0.3"
echo "c) v1.0.4 (Latest version. Must Upgrade before January 28, 2026 at 00:00 UTC)"

read -p "Enter the letter corresponding to the version: " choice

read -p "Are you sure you want to proceed with the update? (yes/no): " confirm
confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')
if [[ "$confirm" != "yes" ]]; then
    echo "Update cancelled."
    exit 0
fi

case $choice in
    a)
        update_version "v1.0.2" "$BASE_URL/1.0.2"
        ;;
    b)
        update_version "v1.0.3" "$BASE_URL/1.0.3"
        ;;
    c)
        update_version "v1.0.4" "$BASE_URL/1.0.4"
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

echo "Let's Buidl 0G Together!"

