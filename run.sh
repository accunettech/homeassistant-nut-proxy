#!/bin/bash
exec /opt/ups-monitor/venv/bin/python /opt/ups-monitor/ups_monitor.py 2> >(grep -v "Init SSL without certificate database" >&2)

