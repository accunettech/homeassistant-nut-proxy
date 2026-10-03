# Home Assistant NUT proxy

Publish UPS status from Network UPS Tools (NUT) to an MQTT broker for Home Assistant. The Python monitor polls `upsc` every two seconds and publishes changed statuses as retained messages to `NUT/ups/status`.

## Prerequisites

- Linux with systemd and sudo access for service installation.
- Python 3 with virtual environment support.
- NUT's `upsc` command and a working NUT server/UPS driver.
- A reachable MQTT broker with credentials allowed to publish to the configured topic. These are separate from NUT monitor credentials.

On Debian/Ubuntu, install the packages:

```bash
sudo apt update
sudo apt install nut-client nut-server python3 python3-venv git
```

The following NUT examples assume a locally attached USB UPS named `myups` that supplies power to this host. Adapt the driver and configuration to your UPS. If NUT is already working, keep your existing configuration and verify it instead.

## Configure NUT before installing the proxy

Edit `/etc/nut/nut.conf` and set:

```ini
MODE=standalone
```

Define the UPS in `/etc/nut/ups.conf`. For a supported USB HID UPS:

```ini
[myups]
    driver = usbhid-ups
    port = auto
    desc = "Local UPS"
```

In `/etc/nut/upsd.conf`, ensure the server listens locally:

```text
LISTEN 127.0.0.1 3493
LISTEN ::1 3493
```

Create a NUT monitor account in `/etc/nut/upsd.users`, replacing the example password:

```ini
[monuser]
    password = CHANGE_ME
    upsmon primary
```

This is a NUT account, not a Linux user. In `/etc/nut/upsmon.conf`, add or update these settings without leaving duplicate directives:

```text
MONITOR myups@localhost 1 monuser CHANGE_ME primary
MINSUPPLIES 1
SHUTDOWNCMD "/sbin/shutdown -h +0"
POWERDOWNFLAG /etc/killpower
```

Use the same username, password, and role in both files. The power value `1` means this UPS supplies one power supply on this host. This configuration enables NUT's automatic shutdown protection when power becomes critical. For other arrangements, follow the [NUT configuration guide](https://networkupstools.org/docs/user-manual.chunked/ar01s06.html) and [upsmon configuration reference](https://networkupstools.org/docs/man/upsmon.conf.html).

Start NUT after configuring it:

```bash
sudo systemctl enable --now nut.target nut-server nut-monitor
sudo systemctl restart nut-server
sudo systemctl restart nut-monitor
systemctl status nut-server nut-monitor --no-pager
upsc myups@localhost
```

Driver startup is handled by your distribution's NUT integration; consult its driver services if `upsc` reports that the driver is not connected. Confirm `upsc` returns `ups.status` and other live readings before proceeding. If you only changed `/etc/nut/upsd.users`, reload the credentials with `sudo systemctl reload nut-server`.

The proxy reads public UPS status using `upsc`; it does not use the `monuser` credentials. `nut-monitor` provides the host shutdown protection separately.

## Configure Python and MQTT

From your checkout, create the virtual environment as the regular user who will run the service:

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

Edit the configuration at the top of `ups_monitor.py`:

| Setting | Purpose |
| --- | --- |
| `UPS_NAME` | UPS identifier, such as `myups` or `myups@server` |
| `MQTT_BROKER` | MQTT broker hostname or IP address |
| `MQTT_PORT` | Broker port; default is `1883` |
| `MQTT_USERNAME`, `MQTT_PASSWORD` | Your broker credentials |
| `MQTT_TOPIC` | Topic for retained UPS status messages |
| `POLL_INTERVAL` | Seconds between UPS status checks |

Ensure the service user can resolve the broker hostname and reach its port. Keep your real credentials out of commits.

## Install and start the service

Run as your regular user:

```bash
./setup.sh
```

The script checks the existing virtual environment and MQTT dependency, renders `homeassistant-nut-proxy.service` using the checkout's absolute path and your username, installs it under `/etc/systemd/system`, reloads systemd, enables startup at boot, and restarts the monitor. It prompts for sudo authentication when needed. It does not install packages or configure NUT or MQTT.

The service runs Python directly in the background and retries exits after 10 seconds. Keep the checkout and virtual environment in place: the service references their absolute paths. You can rerun `setup.sh` after moving the checkout or changing the service template; it updates and restarts the same service.

## Manage the service

```bash
# Status and live logs
systemctl status homeassistant-nut-proxy --no-pager
journalctl -u homeassistant-nut-proxy -f

# Restart after editing Python or MQTT settings
sudo systemctl restart homeassistant-nut-proxy

# Stop and disable startup at boot
sudo systemctl disable --now homeassistant-nut-proxy
```

## Troubleshooting

- `upsc: command not found`: install `nut-client`.
- `Connection failure` or `Driver not connected`: check the NUT server and UPS driver before starting the proxy.
- `Fatal error: insufficient power configured`: verify an active `MONITOR` line has the appropriate power value for `MINSUPPLIES`.
- `ERR ACCESS-DENIED` in `nut-monitor`: match the monitor credentials and role in `upsmon.conf` and `upsd.users`, reload `nut-server`, then restart `nut-monitor`.
- Missing virtual environment or MQTT module: complete the Python installation steps above.
- MQTT connection errors: check broker address, reachability, and credentials in `ups_monitor.py` and inspect the proxy's journal.
- `Init SSL without certificate database`: NUT may print this diagnostic even when `upsc` successfully returns UPS readings; inspect the readings and other errors to determine whether communication works.
