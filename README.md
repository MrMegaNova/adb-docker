# adb-docker

A small Docker image that runs an [Android Debug Bridge](https://developer.android.com/tools/adb) (`adb`) server, giving you access to platform tools such as `adb` and `fastboot` from inside a container.

> This repository is a fork of [tiiuae/adb-docker](https://github.com/tiiuae/adb-docker), which itself derives from [sorccu/adb](https://github.com/sorccu/docker-adb). It is based on Alpine to keep the image small and adds an entrypoint that starts the ADB server and sets up reverse port forwarding (`tcp:9696` and `tcp:4223`) automatically once a device connects.

## Image

```
ghcr.io/mrmeganova/adb-docker:latest
```

Pull it with:

```sh
docker pull ghcr.io/mrmeganova/adb-docker:latest
```

## Requirements

The container needs access to the host's USB bus to talk to a physical device:

* It must run with `--privileged`.
* The host's `/dev/bus/usb` must be mounted into the container.

## Quick start

Start the ADB server and expose it on the host:

```sh
docker run -d --privileged \
  -v /dev/bus/usb:/dev/bus/usb \
  -p 5037:5037 \
  --name adbd \
  ghcr.io/mrmeganova/adb-docker:latest
```

Plug in your device, then list it:

```sh
docker exec adbd adb devices
```

You should see something like:

```
List of devices attached
0123456789ABCDEF	device
```

## Examples

### Run a one-off adb command

```sh
docker run --rm --privileged \
  -v /dev/bus/usb:/dev/bus/usb \
  ghcr.io/mrmeganova/adb-docker:latest \
  adb devices
```

### Open a shell on the device

```sh
docker exec -it adbd adb shell
```

### Install an APK

```sh
docker run --rm --privileged \
  -v /dev/bus/usb:/dev/bus/usb \
  -v "$PWD:/apks" \
  ghcr.io/mrmeganova/adb-docker:latest \
  adb install /apks/app.apk
```

### Connect from a remote machine

With the server running and `5037` published (see [Quick start](#quick-start)), point a remote `adb` client at the host:

```sh
adb -H <server-ip> -P 5037 devices
```

## Security

The image ships with a built-in RSA key so you don't have to authorize a new key on the device every time the container starts. This is convenient, but it means anyone holding that key can reach your device over ADB. To use your own key instead, mount your key folder over `/root/.android`:

```sh
docker run -d --privileged \
  -v /dev/bus/usb:/dev/bus/usb \
  -v /your/key_folder:/root/.android \
  -p 5037:5037 \
  --name adbd \
  ghcr.io/mrmeganova/adb-docker:latest
```

## Scripts

The [scripts/](scripts/) folder contains debloat and configuration scripts for Android
devices (TV and smartphone), meant to be run through this container. See
[scripts/README.md](scripts/README.md) for details.

## Systemd units

Sample [systemd](https://www.freedesktop.org/wiki/Software/systemd/) units are provided in the [systemd/](systemd/) folder to run the daemon as a managed service. Copy them to `/etc/systemd/system/`, then:

```sh
systemctl enable --now adbd
```

Run `systemctl daemon-reload` after editing any unit.

## License

See [LICENSE](LICENSE).
