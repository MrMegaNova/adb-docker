FROM alpine:3.24.1

# Set up insecure default key
RUN mkdir -m 0750 /root/.android
ADD files/insecure_shared_adbkey /root/.android/adbkey
ADD files/insecure_shared_adbkey.pub /root/.android/adbkey.pub

RUN set -xeo pipefail && \
    apk update && \
    apk add android-tools wget ca-certificates tini && \
    rm -r /var/cache/apk/APKINDEX.* && \
    adb --version

# Expose default ADB port
EXPOSE 5037

# Create startup script
RUN cat > /usr/local/bin/start-adb.sh <<'SH' && chmod +x /usr/local/bin/start-adb.sh
#!/bin/sh
set -e

echo "[adb] Starting ADB server on port 5037..."
adb -a -P 5037 server nodaemon &
sleep 2

echo "[adb] Monitoring for device connections..."
DEVICE_CONNECTED=false

while true; do
  if adb get-state 1>/dev/null 2>&1; then
    # Device is connected
    if [ "$DEVICE_CONNECTED" = "false" ]; then
      echo "[adb] Device connected, setting up reverse ports..."
      adb reverse tcp:9696 tcp:9696 || true
      adb reverse tcp:4223 tcp:4223 || true
      DEVICE_CONNECTED=true
    fi
  else
    # Device is NOT connected
    if [ "$DEVICE_CONNECTED" = "true" ]; then
      echo "[adb] Device disconnected"
      DEVICE_CONNECTED=false
    fi
  fi
  sleep 3
done
SH


# Use tini for proper signal handling
ENTRYPOINT ["/sbin/tini", "--"]

# Automatically start everything (server + reverse)
CMD ["/usr/local/bin/start-adb.sh"]
