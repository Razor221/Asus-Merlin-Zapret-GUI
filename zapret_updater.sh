#!/bin/sh

# 1. Auto-detect architecture and map to Zapret release folders
ARCH=$(uname -m)
case "$ARCH" in
    aarch64|arm64) 
        TARGET="linux-arm64" 
        ;;
    armv7l|armv7|arm|armv8l) 
        TARGET="linux-arm" 
        ;;
    x86_64|amd64) 
        TARGET="linux-x86_64" 
        ;;
    i?86|x86) 
        TARGET="linux-x86" 
        ;;
    mipsel) 
        TARGET="linux-mipsel" 
        ;;
    mips64) 
        TARGET="linux-mips64" 
        ;;
    mips) 
        TARGET="linux-mips" 
        ;;
    *) 
        echo "Error: Unsupported architecture ($ARCH). Exiting."
        exit 1 
        ;;
esac

echo "Architecture detected: $ARCH -> Mapping to $TARGET"
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
# Use the dynamic $TARGET variable instead of hardcoded linux-arm64
NFQWS_BIN=$(find /tmp/zapret_update -name "nfqws" | grep "$TARGET")
TPWS_BIN=$(find /tmp/zapret_update -name "tpws" | grep "$TARGET")
BLOCKCHECK_BIN=$(find /tmp/zapret_update -name "blockcheck.sh" | head -n 1)

if [ -n "$NFQWS_BIN" ] && [ -n "$TPWS_BIN" ]; then
    cp "$NFQWS_BIN" /opt/zapret/nfq/
    cp "$TPWS_BIN" /opt/zapret/tpws/
    cp "$BLOCKCHECK_BIN" /opt/zapret/
    chmod +x /opt/zapret/nfq/nfqws /opt/zapret/tpws/tpws /opt/zapret/blockcheck.sh
    echo "Binaries updated successfully for $TARGET."
else
    echo "Error: Could not locate $TARGET binaries in the extracted archive."
fi

echo "Starting Zapret service..."
/opt/zapret/init.d/sysv/zapret start

echo "Cleaning up..."
rm -rf /tmp/zapret_update

# Regenerate the static Web UI HTML to show the final log
/jffs/addons/zapret-gui/zapret-gui.sh status
