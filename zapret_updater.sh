#!/bin/sh

echo "Fetching latest Zapret release tag..."
TAG=$(curl -k -s -L -4 --connect-timeout 10 -m 15 https://api.github.com/repos/bol-van/zapret/releases/latest | grep '"tag_name":' | awk -F'"' '{print $4}')

if [ -z "$TAG" ]; then
    echo "Error: Could not retrieve latest tag from GitHub. Exiting."
    exit 1
fi

echo "Downloading embedded Zapret release: $TAG"
mkdir -p /tmp/zapret_update

# Added -s to suppress the progress bar that breaks the Web GUI log
if ! curl -k -s -L -f -o /tmp/zapret_update/zapret-embedded.tar.gz "https://github.com/bol-van/zapret/releases/download/$TAG/zapret-$TAG-openwrt-embedded.tar.gz"; then
    echo "Error: Download failed. Exiting."
    rm -rf /tmp/zapret_update
    exit 1
fi

echo "Extracting archive..."
tar -xzf /tmp/zapret_update/zapret-embedded.tar.gz -C /tmp/zapret_update

echo "Stopping Zapret service..."
/opt/zapret/init.d/sysv/zapret stop

echo "Locating and updating binaries..."
# Removed the incompatible '-type f' argument for AsusWRT's BusyBox
NFQWS_BIN=$(find /tmp/zapret_update -name "nfqws" | grep "linux-arm64")
TPWS_BIN=$(find /tmp/zapret_update -name "tpws" | grep "linux-arm64")
BLOCKCHECK_BIN=$(find /tmp/zapret_update -name "blockcheck.sh" | head -n 1)

if [ -n "$NFQWS_BIN" ] && [ -n "$TPWS_BIN" ]; then
    cp "$NFQWS_BIN" /opt/zapret/nfq/
    cp "$TPWS_BIN" /opt/zapret/tpws/
    cp "$BLOCKCHECK_BIN" /opt/zapret/
    chmod +x /opt/zapret/nfq/nfqws /opt/zapret/tpws/tpws /opt/zapret/blockcheck.sh
    echo "Binaries updated successfully."
else
    echo "Error: Could not locate linux-arm64 binaries in the extracted archive."
fi

echo "Starting Zapret service..."
/opt/zapret/init.d/sysv/zapret start

echo "Cleaning up..."
rm -rf /tmp/zapret_update

# Regenerate the static Web UI HTML to show the final log
/jffs/addons/zapret-gui/zapret-gui.sh status
