#!/bin/bash
# ==============================================
# VPN Server Setup — VERSI FINAL (Sudah Diperbaiki)
# ==============================================

clear
echo "======================================"
echo "   VPN Server Setup (Final Version)"
echo "======================================"

# ==============================================
# LANGKAH 1: Siapkan Sistem & Jaringan
# ==============================================
echo -e "\n[+] Mengaktifkan Penerusan Paket..."
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p

echo -e "\n[+] Mengatur Aturan NAT & Firewall..."
iptables -F
iptables -t nat -F
iptables -t nat -A POSTROUTING -j MASQUERADE
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -p tcp --dport 2000:2010 -j ACCEPT
iptables -A INPUT -p udp --dport 2000:2010 -j ACCEPT

# Simpan iptables jika bisa
if command -v netfilter-persistent &> /dev/null; then
    netfilter-persistent save 2>/dev/null
fi

# ==============================================
# LANGKAH 2: Pasang Xray
# ==============================================
echo -e "\n[+] Memasang Xray..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# ==============================================
# LANGKAH 3: Buat Direktori & Konfigurasi
# ==============================================
mkdir -p /usr/local/etc/xray /var/log/xray

DOMAIN="panel.randi.biz.id"
UUID=$(cat /proc/sys/kernel/random/uuid)
UUID2=$(cat /proc/sys/kernel/random/uuid)

cat > /usr/local/etc/xray/config.json << EOF
{
  "log": {
    "loglevel": "info",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "port": 2000,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/vmess",
          "headers": { "Host": "$DOMAIN" }
        }
      }
    },
    {
      "port": 2001,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID2"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/vless",
          "headers": { "Host": "$DOMAIN" }
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

# ==============================================
# LANGKAH 4: Service Systemd
# ==============================================
cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
User=root
ExecStart=/usr/local/bin/xray -c /usr/local/etc/xray/config.json
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now xray

# ==============================================
# LANGKAH 5: Tampilkan Info
# ==============================================
clear
echo "======================================"
echo "✅ INSTALASI SELESAI!"
echo "======================================"
echo -e "\n📡 VMess (Port 2000):"
echo "Alamat: $DOMAIN"
echo "Port: 2000"
echo "ID: $UUID"
echo "AlterId: 0"
echo "Jaringan: WebSocket"
echo "Path: /vmess"
echo "Protokol: vmess"
echo -e "\n🔗 Link:"
echo "vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"Valkry8-VMess\",\"add\":\"$DOMAIN\",\"port\":\"2000\",\"id\":\"$UUID\",\"aid\":\"0\",\"sc\":\"\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"$DOMAIN\",\"path\":\"/vmess\",\"tls\":\"\"}" | base64 -w 0)"

echo -e "\n📡 VLESS (Port 2001):"
echo "Alamat: $DOMAIN"
echo "Port: 2001"
echo "ID: $UUID2"
echo "Jaringan: WebSocket"
echo "Path: /vless"
echo "Protokol: vless"
echo -e "\n🔗 Link:"
echo "vless://$UUID2@$DOMAIN:2001?path=%2Fvless&security=none&encryption=none&type=ws#Valkry8-VLESS"

echo -e "\n======================================"
echo "✅ NAT & IP Forward Sudah Aktif!"
echo "✅ Xray Berjalan!"
echo "======================================"
