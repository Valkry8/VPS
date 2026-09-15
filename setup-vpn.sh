#!/bin/bash
# ==================================================
#  VPN MANAGER + HPROXY + SSL — VERSI FINAL
#  VERSION: SPV07.01.28
# ==================================================

VERSION="SPV07.01.28"

# ================= KONFIGURASI =================
CLIENT_NAME="Biznet Gio User"
EXPIRY_DAYS=35
DOMAIN="panel.randi.biz.id"
EMAIL="admin@biznet.idgarsell.biz.id"
ISP="PT Biznet Gio Nusantara"
CITY="Bogor"
# =================================================

GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
BLUE='\033[1;34m'
NC='\033[0m'

cek_update() {
  clear
  echo -e "${YELLOW}🔍 Mengecek pembaruan...${NC}"
  wget -q -O /tmp/setup-vpn-new.sh https://raw.githubusercontent.com/Valkry8/VPS/main/setup-vpn.sh
  if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Tidak terhubung ke GitHub${NC}"
    rm -f /tmp/setup-vpn-new.sh; sleep 2; return
  fi
  VERSI_LAMA=$(grep '^VERSION=' /usr/local/bin/setup-vpn.sh | cut -d'"' -f2)
  VERSI_BARU=$(grep '^VERSION=' /tmp/setup-vpn-new.sh | cut -d'"' -f2)
  if [ "$VERSI_LAMA" = "$VERSI_BARU" ] || [ -z "$VERSI_BARU" ]; then
    echo -e "${GREEN}✅ Sudah versi terbaru! ($VERSI_LAMA)${NC}"
    rm -f /tmp/setup-vpn-new.sh; sleep 1; return
  fi
  echo -e "${CYAN}📤 Versi baru: $VERSI_BARU${NC}"
  read -p "Pasang sekarang? (y/n): " jawab
  if [ "$jawab" = "y" ] || [ "$jawab" = "Y" ]; then
    mv /tmp/setup-vpn-new.sh /usr/local/bin/setup-vpn.sh
    chmod +x /usr/local/bin/setup-vpn.sh
    exec /usr/local/bin/setup-vpn.sh
  fi
  rm -f /tmp/setup-vpn-new.sh
}

get_ram() { free -m | awk '/Mem:/ {printf "%dMB / %dMB", $3, $2}'; }
get_ip() { curl -s --connect-timeout 5 ifconfig.me || echo "103.89.3.153"; }
get_uptime() { uptime -p 2>/dev/null | sed 's/up //' || echo "Tidak diketahui"; }
status_xray() { systemctl is-active --quiet xray && echo -e "${GREEN}ON${NC}" || echo -e "${RED}OFF${NC}"; }
status_nginx() { systemctl is-active --quiet nginx && echo -e "${GREEN}ON${NC}" || echo -e "${RED}OFF${NC}"; }
status_hproxy() { systemctl is-active --quiet hproxy && echo -e "${GREEN}ON${NC}" || echo -e "${RED}OFF${NC}"; }
status_ssl() { [ -f /etc/letsencrypt/live/${DOMAIN}/fullchain.pem ] && echo -e "${GREEN}PASANG${NC}" || echo -e "${YELLOW}BELUM${NC}"; }

pasang_ssl() {
  echo -e "${YELLOW}🔐 MEMASANG SERTIFIKAT SSL LET'S ENCRYPT...${NC}"
  
  if ! command -v certbot &>/dev/null; then
    apt install -y certbot python3-certbot-nginx
  fi

  systemctl stop nginx
  certbot certonly --standalone --email "$EMAIL" -d "$DOMAIN" --agree-tos --no-eff-email
  
  if [ -f /etc/letsencrypt/live/${DOMAIN}/fullchain.pem ]; then
    echo -e "${GREEN}✅ SSL BERHASIL DIPASANG!${NC}"
    sed -i "s|ssl_certificate.*;|ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;|" /etc/nginx/sites-available/ssh-ws
    sed -i "s|ssl_certificate_key.*;|ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;|" /etc/nginx/sites-available/ssh-ws
    systemctl restart nginx
    touch /var/log/vpn/ssl-installed
  else
    echo -e "${RED}❌ Gagal pasang SSL. Pastikan domain sudah menunjuk ke IP VPS!${NC}"
    systemctl start nginx
  fi
  sleep 2
}

ubah_domain() {
  print_header
  echo -e "${YELLOW}🌐 GANTI DOMAIN UTAMA${NC}"
  echo -e "Domain sekarang: ${BLUE}${DOMAIN}${NC}"
  read -p "Domain baru: " DOMAIN_BARU
  [ -z "$DOMAIN_BARU" ] && { echo -e "${RED}Kosong!${NC}"; sleep 1; return; }

  sed -i "s|^DOMAIN=\".*\"$|DOMAIN=\"$DOMAIN_BARU\"|" /usr/local/bin/setup-vpn.sh
  DOMAIN="$DOMAIN_BARU"
  
  sed -i "s|server_name[^;]*;|server_name ${DOMAIN};|" /etc/nginx/sites-available/ssh-ws
  systemctl restart nginx 2>/dev/null

  echo -e "${GREEN}✅ Domain diganti!${NC}"
  read -p "Pasang SSL untuk domain baru sekarang? (y/n): " jawab
  if [ "$jawab" = "y" ] || [ "$jawab" = "Y" ]; then
    pasang_ssl
  fi
}

ubah_klien() {
  print_header
  echo -e "${YELLOW}👤 GANTI NAMA KLIEN${NC}"
  read -p "Nama baru: " NAMA_BARU
  sed -i "s|^CLIENT_NAME=\".*\"$|CLIENT_NAME=\"$NAMA_BARU\"|" /usr/local/bin/setup-vpn.sh
  CLIENT_NAME="$NAMA_BARU"
  echo -e "${GREEN}✅ Nama diganti!${NC}"; sleep 1
}

install_all() {
  clear
  echo -e "${YELLOW}🔧 MEMULAI INSTALASI LENGKAP + SSL...${NC}"
  sleep 2

  apt update -y && apt upgrade -y
  apt install -y curl wget nano bc jq openssl net-tools socat

  if ! command -v nginx &>/dev/null; then
    echo -e "${CYAN}📦 Menginstal Nginx...${NC}"
    apt install -y nginx
  fi

  echo -e "${CYAN}📦 Menginstal HProxy...${NC}"
  cat > /usr/local/bin/hproxy <<'EOF'
#!/bin/bash
while true; do
  socat TCP-LISTEN:8080,fork,reuseaddr TCP:127.0.0.1:22 &
  socat TCP-LISTEN:8880,fork,reuseaddr TCP:127.0.0.1:22 &
  wait
done
EOF
  chmod +x /usr/local/bin/hproxy

  cat > /etc/systemd/system/hproxy.service <<'EOF'
[Unit]
Description=HProxy VPN Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/hproxy
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now hproxy

  cat > /etc/nginx/sites-available/ssh-ws <<EOF
server {
    listen 80;
    listen 443 ssl http2;
    server_name ${DOMAIN};

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;

    location /ssh- {
        proxy_pass http://127.0.0.1:22;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_connect_timeout 300s;
    }
    location /vmess- {
        proxy_pass http://127.0.0.1:2000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
    location /vless- {
        proxy_pass http://127.0.0.1:2001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}
EOF

  ln -sf /etc/nginx/sites-available/ssh-ws /etc/nginx/sites-enabled/
  rm -f /etc/nginx/sites-enabled/default

  if ! command -v xray &>/dev/null; then
    echo -e "${CYAN}📦 Menginstal Xray...${NC}"
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
  fi

  mkdir -p /usr/local/etc/xray /var/log/vpn
  touch /var/log/vpn/ssh.log /var/log/vpn/vmess.log /var/log/vpn/vless.log

  cat > /usr/local/etc/xray/config.json <<'EOF'
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {"port":2000,"protocol":"vmess","settings":{"clients":[]},"streamSettings":{"network":"ws","path":"/vmess-"}},
    {"port":2001,"protocol":"vless","settings":{"clients":[]},"streamSettings":{"network":"ws","path":"/vless-"}}
  ],
  "outbounds": [{"protocol":"freedom"}]
}
EOF

  systemctl enable --now nginx xray
  systemctl restart nginx xray

  echo -e "${CYAN}🔐 Memasang Sertifikat SSL...${NC}"
  pasang_ssl

  touch /var/log/vpn/installed
  echo -e "${GREEN}✅ SEMUA BERHASIL DIPASANG!${NC}"
  sleep 2
}

print_header() {
  IP_NOW=$(get_ip)
  clear
  echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${GREEN}     VPN MANAGER + HPROXY + SSL — PREMIUM SCRIPT              ${CYAN}║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "${YELLOW}┌─ SERVER INFO ──────────────────────────────────────────────────┐${NC}"
  echo -e "│ RAM      : $(get_ram)"
  echo -e "│ CITY     : ${CITY}"
  echo -e "│ ISP      : ${ISP}"
  echo -e "│ IP       : ${IP_NOW}"
  echo -e "│ DOMAIN   : ${DOMAIN}"
  echo -e "│ SSL      : $(status_ssl)"
  echo -e "│ UPTIME   : $(get_uptime)"
  echo -e "├─ STATUS ───────────────────────────────────────────────────────┤${NC}"
  echo -e "│ XRAY     : $(status_xray)   NGINX   : $(status_nginx)   HPROXY : $(status_hproxy)"
  echo -e "├─ KLIEN ────────────────────────────────────────────────────────┤${NC}"
  echo -e "│ VERSION  : ${VERSION}"
  echo -e "│ STATUS   : ${GREEN}Gass!! Ready${NC}"
  echo -e "│ CLIENT   : ${CLIENT_NAME}"
  echo -e "│ EXPIRE   : ${YELLOW}${EXPIRY_DAYS} Days${NC}"
  echo -e "└───────────────────────────────────────────────────────────────┘${NC}"
  echo ""
}

buat_ssh() {
  print_header
  read -p "Nama Akun : " user
  read -p "Password  : " pass
  [ -z "$user" ] || [ -z "$pass" ] && { echo -e "${RED}Kosong!${NC}"; sleep 1; return; }
  id -u "$user" >/dev/null 2>&1 && { echo -e "${RED}Sudah ada!${NC}"; sleep 1; return; }

  useradd -m -s /bin/bash "$user" 2>/dev/null
  echo "$user:$pass" | chpasswd
  IP_NOW=$(get_ip)
  echo "$user|$pass|$DOMAIN|/ssh-$user|$IP_NOW|$(date +%Y%m%d)" >> /var/log/vpn/ssh.log

  print_header
  echo -e "${GREEN}✅ AKUN SSH DIBUAT 👇${NC}"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  echo -e "🔒 TLS/SSL + WebSocket (Disarankan)"
  echo -e "  Alamat   : ${BLUE}${DOMAIN}${NC}"
  echo -e "  Port     : ${BLUE}443${NC}"
  echo -e "  Path     : ${BLUE}/ssh-${user}${NC}"
  echo -e "  Username : ${BLUE}${user}${NC}"
  echo -e "  Password : ${BLUE}${pass}${NC}"
  echo -e "  SNI      : ${BLUE}${DOMAIN}${NC}"
  echo ""
  echo -e "🌐 HProxy Langsung"
  echo -e "  Alamat   : ${BLUE}${IP_NOW}${NC}"
  echo -e "  Port     : ${BLUE}8080${NC} / ${BLUE}8880${NC}"
  echo -e "  User/Pass: sama di atas"
  echo ""
  echo -e "📡 Non-TLS WebSocket"
  echo -e "  Alamat   : ${BLUE}${IP_NOW}${NC}"
  echo -e "  Port     : ${BLUE}80${NC}"
  echo -e "  Path     : ${BLUE}/ssh-${user}${NC}"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  read -p "Tekan Enter..."
}

buat_vmess() {
  print_header
  UUID=$(cat /proc/sys/kernel/random/uuid)
  read -p "Nama Akun : " name
  link="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$name\",\"add\":\"$DOMAIN\",\"port\":443,\"id\":\"$UUID\",\"aid\":0,\"scy\":\"auto\",\"net\":\"ws\",\"path\":\"/vmess-$name\",\"type\":\"none\",\"host\":\"$DOMAIN\",\"tls\":\"tls\"}" | base64 -w 0)"
  echo -e "${GREEN}✅ VMESS: ${BLUE}${link}${NC}"; read -p "Enter..."
}

buat_vless() {
  print_header
  UUID=$(cat /proc/sys/kernel/random/uuid)
  read -p "Nama Akun : " name
  link="vless://$UUID@$DOMAIN:443?path=/vless-$name&security=tls&encryption=none&type=ws&sni=$DOMAIN#$name"
  echo -e "${GREEN}✅ VLESS: ${BLUE}${link}${NC}"; read -p "Enter..."
}

buat_trojan() {
  print_header
  pass=$(openssl rand -hex 8)
  read -p "Nama Akun : " name
  link="trojan://$pass@$DOMAIN:443?path=/trojan-$name&security=tls&type=ws&sni=$DOMAIN#$name"
  echo -e "${GREEN}✅ TROJAN Pass: ${BLUE}${pass}${NC}"; echo -e "Link: ${BLUE}${link}${NC}"; read -p "Enter..."
}

if [ ! -f /var/log/vpn/installed ]; then
  install_all
fi

while true; do
  print_header
  echo -e "${CYAN}┌─ MENU ────────────────────────────────────────────────────────┐${NC}"
  echo -e "│  1.) BUAT AKUN SSH + HPROXY     6.) CEK PEMBARUAN             │"
  echo -e "│  2.) BUAT VMESS                 7.) UBAH DOMAIN + SSL        │"
  echo -e "│  3.) BUAT VLESS                 8.) UBAH NAMA KLIEN          │"
  echo -e "│  4.) BUAT TROJAN                9.) PASANG/RENEW SSL          │"
  echo -e "│  5.) DAFTAR AKUN                x.) KELUAR                    │"
  echo -e "└───────────────────────────────────────────────────────────────┘${NC}"
  read -p "Pilih Menu: " pil

  case "$pil" in
    1) buat_ssh ;;
    2) buat_vmess ;;
    3) buat_vless ;;
    4) buat_trojan ;;
    5) clear; echo -e "${YELLOW}📋 DAFTAR AKUN:${NC}"; cat /var/log/vpn/ssh.log 2>/dev/null||echo "Kosong"; read -p "Enter..." ;;
    6) cek_update ;;
    7) ubah_domain ;;
    8) ubah_klien ;;
    9) pasang_ssl ;;
    x|X) echo -e "${GREEN}👋 Sampai jumpa!${NC}"; exit 0 ;;
    *) echo -e "${RED}Pilihan salah!${NC}"; sleep 1 ;;
  esac
done
