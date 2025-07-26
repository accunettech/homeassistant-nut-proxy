#!/usr/bin/env python3
import subprocess
import time
import paho.mqtt.client as mqtt

# CONFIGURATION
UPS_NAME = "myups"                        # the UPS name in your upsd.conf
MQTT_BROKER = "homeassistant.local"        # or IP address of Home Assistant
MQTT_PORT = 1883
MQTT_USERNAME = "mqtt_user"
MQTT_PASSWORD = "mqtt_p@ssw0rd"
MQTT_TOPIC = "NUT/ups/status"
POLL_INTERVAL = 2                          # in seconds

# STATE TRACKING
last_status = None

def get_ups_status():
    try:
        result = subprocess.check_output(["upsc", UPS_NAME], timeout=3).decode()
        for line in result.splitlines():
            if line.startswith("ups.status:"):
                return line.split(":")[1].strip()
    except subprocess.TimeoutExpired:
        print("[WARN] upsc timed out")
    except Exception as e:
        print(f"[ERROR] Failed to run upsc: {e}")
    return "UNKNOWN"

def publish_status(client, status):
    print(f"[MQTT] Publishing status: {status}")
    client.publish(MQTT_TOPIC, status, retain=True)

def main():
    global last_status

    print("########################################")
    print("########  Starting UPS Monitor  ########")
    print("########################################")

    client = mqtt.Client()
    client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)

    print(f"[INFO] Connecting to MQTT broker {MQTT_BROKER}:{MQTT_PORT}...")
    try:
        client.connect(MQTT_BROKER, MQTT_PORT, 60)
    except Exception as e:
        print(f"[FATAL] Could not connect to MQTT broker: {e}")
        return

    client.loop_start()

    while True:
        status = get_ups_status()
        if status != last_status and status != "UNKNOWN":
            publish_status(client, status)
            last_status = status
        time.sleep(POLL_INTERVAL)

if __name__ == "__main__":
    main()

