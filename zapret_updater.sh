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
TAG=$(curl -s -L -4 --connect-timeout 10 -m 15 https://api.github.com/repos/bol-van/zapret/releases/latest | grep '"tag_name":' | awk -F'"' '{print $4}')

if [ -z "$TAG" ]; then
    echo "Error: Could not retrieve latest tag from GitHub. Exiting."
    exit 1
fi

echo "Downloading embedded Zapret release: $TAG"
mkdir -p /tmp/zapret_update

# Added -s to suppress the progress bar that breaks the Web GUI log. Removed -k for security.
if ! curl -s -L -f -o /tmp/zapret_update/zapret-embedded.tar.gz "https://github.com/bol-van/zapret/releases/download/$TAG/zapret-$TAG-openwrt-embedded.tar.gz"; then
    echo "Error: Download failed. Exiting."
    rm -rf /tmp/zapret_update
    exit 1
fi

echo "Downloading checksum file..."
if ! curl -s -L -f -o /tmp/zapret_update/sha256sum.txt "https://github.com/bol-van/zapret/releases/download/$TAG/sha256sum.txt"; then
    echo "Error: Failed to download sha256sum.txt. Exiting."
    rm -rf /tmp/zapret_update
    exit 1
fi

echo "Verifying checksum..."
cd /tmp/zapret_update
if ! grep "zapret-$TAG-openwrt-embedded.tar.gz" sha256sum.txt | sha256sum -c -; then
    echo "Error: Checksum verification failed! The file might be corrupted or compromised."
    cd /
    rm -rf /tmp/zapret_update
    exit 1
fi
cd /

echo "Extracting archive..."
tar -xzf /tmp/zapret_update/zapret-embedded.tar.gz -C /tmp/zapret_update

# Provide temporary locking functions to prevent GUI Watchdog from interfering
LOCK_CONF="/tmp/zapret-gui-lock-conf"
Lock_Acquire() {
	local l="$1" timeout="$2" p i=0
	while [ "$i" -lt "$timeout" ]; do
		if mkdir "$l" 2>/dev/null; then return 0; fi
		p="$(cat "$l/pid" 2>/dev/null)"
		if [ -z "$p" ] || ! kill -0 "$p" 2>/dev/null; then
			rm -rf "$l"; mkdir "$l" 2>/dev/null && { echo "$$" > "$l/pid"; return 0; }
		fi
		sleep 1; i=$((i+1))
	done
	return 1
}
Lock_Release() { rm -rf "$1"; }

echo "Acquiring lock and stopping Zapret service..."
if Lock_Acquire "$LOCK_CONF" 15; then
    /opt/zapret/init.d/sysv/zapret stop
else
    echo "Warning: Could not acquire lock, Watchdog might restart the service during update."
    /opt/zapret/init.d/sysv/zapret stop
fi

echo "Locating and updating binaries..."
# Use strict path matching to avoid matching wrong architectures (e.g. linux-arm matching linux-arm64)
NFQWS_BIN=$(find /tmp/zapret_update -path "*/binaries/$TARGET/nfqws" | head -n 1)
TPWS_BIN=$(find /tmp/zapret_update -path "*/binaries/$TARGET/tpws" | head -n 1)
BLOCKCHECK_BIN=$(find /tmp/zapret_update -name "blockcheck.sh" | head -n 1)
COMMON_DIR=$(find /tmp/zapret_update -type d -name "common" | head -n 1)

if [ -n "$NFQWS_BIN" ] && [ -n "$TPWS_BIN" ]; then
    # Backup before replacing
    cp /opt/zapret/nfq/nfqws /opt/zapret/nfq/nfqws.bak 2>/dev/null
    cp /opt/zapret/tpws/tpws /opt/zapret/tpws/tpws.bak 2>/dev/null
    
    # Overwrite the binaries
    cp "$NFQWS_BIN" /opt/zapret/nfq/
    cp "$TPWS_BIN" /opt/zapret/tpws/
    
    # Update blockcheck and its dependencies (common dir)
    if [ -n "$BLOCKCHECK_BIN" ]; then
        cp "$BLOCKCHECK_BIN" /opt/zapret/
        chmod +x /opt/zapret/blockcheck.sh
    fi
    if [ -n "$COMMON_DIR" ]; then
        rm -rf /opt/zapret/common
        cp -r "$COMMON_DIR" /opt/zapret/
    fi
    
    chmod +x /opt/zapret/nfq/nfqws /opt/zapret/tpws/tpws
    echo "Binaries updated successfully for $TARGET."
else
    echo "Error: Could not locate $TARGET binaries in the extracted archive."
fi

echo "Starting Zapret service..."
/opt/zapret/init.d/sysv/zapret start
Lock_Release "$LOCK_CONF"

echo "Cleaning up..."
rm -rf /tmp/zapret_update

# Regenerate the static Web UI HTML to show the final log
/jffs/addons/zapret-gui/zapret-gui.sh status
