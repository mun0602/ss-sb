#!/bin/bash

# Script cài đặt SingBox và tạo cấu hình Shadowsocks (SS) trên Ubuntu
# Chạy script với quyền sudo: sudo bash install_singbox_ss.sh

# Kiểm tra quyền root
if [ "$EUID" -ne 0 ]; then
  echo "Vui lòng chạy script với quyền sudo"
  exit 1
fi

# Cập nhật danh sách gói phần mềm
echo "===== Cập nhật danh sách gói phần mềm ====="
apt update

# Cài đặt các công cụ cần thiết
echo "===== Cài đặt các công cụ cần thiết ====="
apt install -y curl wget unzip jq

# Tạo thư mục làm việc
WORK_DIR="/opt/singbox"
mkdir -p $WORK_DIR
cd $WORK_DIR

# Tải SingBox từ URL được chỉ định
echo "===== Tải SingBox từ URL được chỉ định ====="
DOWNLOAD_URL="https://dtdp.bio/wp-content/apk/git/sing-box-1.11.4-linux-amd64.tar.gz"

wget -O singbox.tar.gz $DOWNLOAD_URL
tar -xzf singbox.tar.gz
mv sing-box-1.11.4-linux-amd64/* ./
rm -rf sing-box-1.11.4-linux-amd64 singbox.tar.gz

# Cấu hình SingBox
echo "===== Cấu hình SingBox ====="

# Tạo mật khẩu ngẫu nhiên
PASSWORD=$(openssl rand -base64 16)
# Chọn cổng ngẫu nhiên (1024-65535)
PORT=$(shuf -i 10000-65000 -n 1)
# Lấy địa chỉ IP công khai
SERVER_IP=$(curl -s https://api.ipify.org)

# Tạo file cấu hình
cat > $WORK_DIR/config.json << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "::",
      "listen_port": $PORT,
      "method": "chacha20-ietf-poly1305",
      "password": "$PASSWORD",
      "network": "tcp,udp"
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "rules": [
      {
        "geoip": "private",
        "outbound": "direct"
      }
    ],
    "final": "direct"
  }
}
EOF

# Tạo service systemd
cat > /etc/systemd/system/singbox.service << EOF
[Unit]
Description=SingBox Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$WORK_DIR
ExecStart=$WORK_DIR/sing-box run -c $WORK_DIR/config.json
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

# Cấp quyền thực thi
chmod +x $WORK_DIR/sing-box

# Khởi động service
systemctl daemon-reload
systemctl enable singbox
systemctl start singbox

# Yêu cầu người dùng nhập tên cho kết nối
echo
echo "Nhập tên cho kết nối Shadowsocks của bạn (để trống nếu không muốn đặt tên):"
read -r SS_NAME

# Tạo SS URL
METHOD="chacha20-ietf-poly1305"
BASE64_PART=$(echo -n ${METHOD}:${PASSWORD} | base64 | tr -d '\n')

if [ -n "$SS_NAME" ]; then
  SS_URI="ss://${BASE64_PART}@${SERVER_IP}:${PORT}#$(echo -n $SS_NAME | jq -sRr @uri)"
else
  SS_URI="ss://${BASE64_PART}@${SERVER_IP}:${PORT}"
fi

SS_URI_QR=$(echo -n $SS_URI | base64 | tr -d '\n')

# In thông tin
echo
echo "===== SingBox với Shadowsocks đã được cài đặt thành công! ====="
echo
echo "Thông tin Shadowsocks:"
echo "Server: $SERVER_IP"
echo "Port: $PORT"
echo "Mật khẩu: $PASSWORD"
echo "Phương thức mã hóa: $METHOD"
if [ -n "$SS_NAME" ]; then
  echo "Tên kết nối: $SS_NAME"
fi
echo
echo "URL Shadowsocks: $SS_URI"
echo
echo "URL QR Code: $SS_URI_QR"
echo
echo "Để kiểm tra trạng thái: systemctl status singbox"
echo "Để xem logs: journalctl -u singbox -f"
echo
echo "Cấu hình SingBox được lưu tại: $WORK_DIR/config.json"
echo

# Mở cổng trên firewall nếu có UFW
if command -v ufw &> /dev/null; then
  ufw allow $PORT/tcp
  ufw allow $PORT/udp
  echo "Đã mở cổng $PORT trên UFW firewall"
fi
