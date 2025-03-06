#!/bin/bash

# Script cài đặt Shadowsocks đơn giản trên Ubuntu
# Chạy với quyền sudo: sudo bash install_ss.sh

# Kiểm tra quyền root
if [ "$EUID" -ne 0 ]; then
  echo "Vui lòng chạy script với quyền sudo"
  exit 1
fi

# Màu sắc để hiển thị
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Cập nhật danh sách gói phần mềm
echo -e "${YELLOW}[1] Cập nhật danh sách gói phần mềm...${NC}"
apt update -q

# Cài đặt các gói cần thiết
echo -e "${YELLOW}[2] Cài đặt các gói cần thiết...${NC}"
apt install -y -q python3-pip net-tools curl wget qrencode

# Cài đặt Shadowsocks thông qua pip
echo -e "${YELLOW}[3] Cài đặt Shadowsocks...${NC}"
pip3 install shadowsocks

# Tạo thư mục cấu hình
CONF_DIR="/etc/shadowsocks"
mkdir -p $CONF_DIR

# Tạo mật khẩu ngẫu nhiên (16 ký tự)
PASSWORD=$(openssl rand -base64 12 | tr -d '/+=' | head -c 16)

# Chọn cổng ngẫu nhiên (10000-60000)
PORT=$(shuf -i 10000-60000 -n 1)

# Lấy địa chỉ IP công khai
SERVER_IP=$(curl -s https://api.ipify.org)

# Chọn phương thức mã hóa
METHOD="aes-256-cfb"  # Phương thức mã hóa phổ biến, tương thích tốt với hầu hết các client

# Tạo file cấu hình
echo -e "${YELLOW}[4] Tạo cấu hình Shadowsocks...${NC}"
CONFIG_FILE="$CONF_DIR/config.json"

cat > $CONFIG_FILE << EOF
{
  "server": "0.0.0.0",
  "server_port": $PORT,
  "password": "$PASSWORD",
  "method": "$METHOD",
  "timeout": 300,
  "fast_open": true
}
EOF

# Tạo service file
echo -e "${YELLOW}[5] Tạo systemd service...${NC}"
SERVICE_FILE="/etc/systemd/system/shadowsocks.service"

cat > $SERVICE_FILE << EOF
[Unit]
Description=Shadowsocks Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ssserver -c $CONFIG_FILE
Restart=on-failure
RestartSec=5
LimitNOFILE=32768

[Install]
WantedBy=multi-user.target
EOF

# Mở cổng trên tường lửa
echo -e "${YELLOW}[6] Cấu hình tường lửa...${NC}"

# Kiểm tra và mở cổng với UFW
if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
  echo "Mở cổng $PORT trong UFW..."
  ufw allow $PORT/tcp
  ufw allow $PORT/udp
fi

# Mở cổng với iptables
echo "Mở cổng $PORT trong iptables..."
iptables -I INPUT -p tcp --dport $PORT -j ACCEPT
iptables -I INPUT -p udp --dport $PORT -j ACCEPT

# Khởi động dịch vụ
echo -e "${YELLOW}[7] Khởi động dịch vụ Shadowsocks...${NC}"
systemctl daemon-reload
systemctl enable shadowsocks
systemctl start shadowsocks

# Kiểm tra trạng thái dịch vụ
sleep 3
if systemctl is-active --quiet shadowsocks; then
  echo -e "${GREEN}✅ Dịch vụ Shadowsocks đã được khởi động thành công!${NC}"
else
  echo -e "${RED}❌ Không thể khởi động dịch vụ Shadowsocks.${NC}"
  echo "Xem logs: systemctl status shadowsocks"
  exit 1
fi

# Kiểm tra cổng
if netstat -tuln | grep -q ":$PORT "; then
  echo -e "${GREEN}✅ Cổng $PORT đang được lắng nghe.${NC}"
else
  echo -e "${RED}❌ Cổng $PORT không được lắng nghe.${NC}"
  echo "Kiểm tra logs: journalctl -u shadowsocks -f"
  exit 1
fi

# Tạo URL Shadowsocks
echo -e "${YELLOW}[8] Tạo thông tin kết nối...${NC}"

# Yêu cầu người dùng nhập tên
echo -e "${YELLOW}Nhập tên cho kết nối Shadowsocks (để trống nếu không cần):${NC}"
read -r SS_NAME

# Tạo URL
USER_PASS="${METHOD}:${PASSWORD}"
BASE64_USER_PASS=$(echo -n "$USER_PASS" | base64 | tr -d '\n')

if [ -n "$SS_NAME" ]; then
  # URL encode tên
  ENCODED_NAME=$(echo -n "$SS_NAME" | tr -d '\n' | xxd -plain | sed 's/\(..\)/%\1/g')
  SS_URI="ss://${BASE64_USER_PASS}@${SERVER_IP}:${PORT}#${ENCODED_NAME}"
else
  SS_URI="ss://${BASE64_USER_PASS}@${SERVER_IP}:${PORT}"
fi

# Tạo QR code
QRCODE_PATH="/tmp/ss_qrcode.png"
qrencode -s 8 -o "$QRCODE_PATH" "$SS_URI"

# Hiển thị QR code trực tiếp trong terminal
echo -e "${YELLOW}[9] Hiển thị QR code để quét:${NC}"
qrencode -t ANSI "$SS_URI"

# Tạo script để hiển thị thông tin kết nối
INFO_SCRIPT="/usr/local/bin/ss-info"
cat > $INFO_SCRIPT << EOF
#!/bin/bash
echo "============================================"
echo "🔐 Thông tin kết nối Shadowsocks 🔐"
echo "============================================"
echo "◉ Server: $SERVER_IP"
echo "◉ Port: $PORT"
echo "◉ Mật khẩu: $PASSWORD"
echo "◉ Phương thức mã hóa: $METHOD"
if [ -n "$SS_NAME" ]; then
  echo "◉ Tên kết nối: $SS_NAME"
fi
echo "◉ URL: $SS_URI"
echo "============================================"
echo "📱 QR Code hiển thị ở trên (quét bằng ứng dụng Shadowsocks trên điện thoại)"
echo "📱 QR Code cũng được lưu tại: $QRCODE_PATH"
echo "🔄 Kiểm tra trạng thái: systemctl status shadowsocks"
echo "📋 Logs: journalctl -u shadowsocks -f"
echo "🛠️ Cấu hình: $CONFIG_FILE"
echo "============================================"
EOF

chmod +x $INFO_SCRIPT

# In thông tin kết nối
$INFO_SCRIPT

# Kiểm tra kết nối tới Google 
echo -e "${YELLOW}[9] Kiểm tra kết nối internet...${NC}"
if curl -s --max-time 5 https://www.google.com > /dev/null; then
  echo -e "${GREEN}✅ Máy chủ có kết nối internet!${NC}"
else
  echo -e "${RED}⚠️ Không thể kết nối tới Google. Vui lòng kiểm tra kết nối internet.${NC}"
fi

echo -e "${GREEN}Cài đặt hoàn tất!${NC}"
echo -e "${YELLOW}Để xem lại thông tin kết nối, chạy: ss-info${NC}"
