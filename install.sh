#!/bin/bash
wget -q -O /usr/local/bin/setup-vpn.sh https://raw.githubusercontent.com/Valkry8/VPS/main/setup-vpn.sh
chmod +x /usr/local/bin/setup-vpn.sh
exec /usr/local/bin/setup-vpn.sh
