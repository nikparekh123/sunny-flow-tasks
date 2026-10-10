#!/bin/sh
# THETADATA_API_KEY and PROXY_KEY arrive as Fly secrets.
cd /app
java -Xmx640m -jar ThetaTerminalv3.jar &
exec python3 /app/proxy.py
