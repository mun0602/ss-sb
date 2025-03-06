# Kiểm tra hệ thống có cài đặt Shadowsocks client để test không
echo "===== Thử kết nối tự động ====="
if command -v sslocal &> /dev/null; then
  echo "Tìm thấy Shadowsocks client, thử kết nối..."
  # Tạo file cấu hình tạm thời
  SS_TEST_CONFIG="/tmp/ss_test_config.json"
  cat > $SS_TEST_CONFIG << EOF
{
  "server": "$SERVER_IP",
  "server_port": $PORT,
  "password": "$PASSWORD",
  "method": "$METHOD",
  "local_address": "127.0.0.1",
  "local_port": 1080,
  "timeout": 300
}
EOF
  
  # Khởi động sslocal ở background
  sslocal -c $SS_TEST_CONFIG -d start &>/dev/null
  
  # Thử kết nối qua proxy
  echo "Thử kết nối đến google.com qua Shadowsocks..."
  curl --socks5 127.0.0.1:1080 -s -m 5 https://www.google.com > /dev/null
  if [ $? -eq 0 ]; then
    echo "✅ Kết nối thành công! Shadowsocks hoạt động đúng."
  else
    echo "❌ Kết nối thất bại."
  fi
  
  # Dừng sslocal
  sslocal -d stop &>/dev/null
  rm -f $SS_TEST_CONFIG
else
  echo "Không tìm thấy Shadowsocks client để test."
  echo "Để kiểm tra kết nối, bạn có thể cài đặt Shadowsocks client:"
  echo "pip3 install shadowsocks"
fi# Thêm hướng dẫn cấu hình V2Ray để kết nối tới Shadowsocks
cat > $WORK_DIR/v2ray_config_example.json << EOF
{
  "inbounds": [
    {
      "port": 1080,
      "listen": "127.0.0.1",
      "protocol": "socks",
      "settings": {
        "udp": true
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "shadowsocks",
      "settings": {
        "servers": [
          {
            "address": "$SERVER_IP",
            "port": $PORT,
            "method": "$METHOD",
            "password": "$PASSWORD"
          }
        ]
      }
    }
  ]
}
EOF

echo "Đã tạo ví dụ cấu hình V2Ray tại: $WORK_DIR/v2ray_config_example.json"
echo
echo "Để sử dụng với V2Ray, hãy sao chép nội dung file cấu hình này vào config.json của V2Ray"
echo# Kiểm tra kết nối
echo
echo "===== Kiểm tra dịch vụ Shadowsocks ====="
echo
echo "Kiểm tra trạng thái dịch vụ:"
systemctl status singbox | head -n 3
echo
echo "Kiểm tra cổng đang lắng nghe:"
ss -tulpn | grep $PORT || echo "⚠️ Không phát hiện cổng $PORT đang lắng nghe"
echo
echo "Để kiểm tra đầy đủ, chạy script kiểm tra:"
echo "sudo $WORK_DIR/check_ss.sh"
echo# Tạo script kiểm tra kết nối
cat > $WORK_DIR/check_ss.sh << EOF
#!/bin/bash

echo "===== Kiểm tra dịch vụ Shadowsocks ====="
echo

# Kiểm tra service có đang chạy
if systemctl is-active --quiet singbox; then
  echo "✅ Dịch vụ SingBox đang chạy"
else
  echo "❌ Dịch vụ SingBox KHÔNG chạy"
  echo "Thử khởi động lại: sudo systemctl restart singbox"
  echo "Kiểm tra logs: sudo journalctl -u singbox -f"
  exit 1
fi

# Kiểm tra cổng có đang lắng nghe
if netstat -tuln | grep -q ":$PORT "; then
  echo "✅ Cổng $PORT đang được lắng nghe"
else
  echo "❌ Cổng $PORT KHÔNG được lắng nghe"
  echo "Kiểm tra logs: sudo journalctl -u singbox -f"
  exit 1
fi

# Kiểm tra kết nối từ localhost đến cổng
timeout 5 curl --socks5 127.0.0.1:$PORT -s https://www.google.com > /dev/null
if [ \$? -eq 0 ]; then
  echo "✅ Kết nối từ localhost đến Shadowsocks thành công"
else
  echo "❌ Kết nối từ localhost đến Shadowsocks thất bại"
fi

# Kiểm tra tường lửa 
if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
  if ufw status | grep -q "$PORT"; then
    echo "✅ Cổng $PORT đã được mở trên UFW"
  else
    echo "❌ Cổng $PORT chưa được mở trên UFW"
    echo "Chạy: sudo ufw allow $PORT/tcp && sudo ufw allow $PORT/udp"
  fi
fi

echo
echo "Thông tin cấu hình:"
echo "Server: $SERVER_IP"
echo "Port: $PORT"
echo "Mật khẩu: $PASSWORD"
echo "Phương thức mã hóa: $METHOD"
echo
echo "URL Shadowsocks: $SS_URI"
echo
echo "Cấu hình SingBox được lưu tại: $WORK_DIR/config.json"
EOF

chmod +x $WORK_DIR/check_ss.sh#!/bin/bash

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
apt install -y curl wget unzip jq qrencode

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

# Tạo mật khẩu ngẫu nhiên (16 ký tự an toàn)
PASSWORD=$(openssl rand -base64 12 | tr -d '/+=' | head -c 16)
# Chọn cổng ngẫu nhiên (10000-65000)
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
      "listen": "0.0.0.0",
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

# Tạo SS URL tương thích v2ray (sử dụng định dạng chuẩn)
METHOD="chacha20-ietf-poly1305"
USER_PASS="${METHOD}:${PASSWORD}"
BASE64_PART=$(echo -n "$USER_PASS" | base64 | tr -d '\n' | tr -d '=' | tr '+/' '-_')

if [ -n "$SS_NAME" ]; then
  # URL encode tên
  ENCODED_NAME=$(echo -n "$SS_NAME" | jq -sRr @uri)
  SS_URI="ss://${BASE64_PART}@${SERVER_IP}:${PORT}#${ENCODED_NAME}"
else
  SS_URI="ss://${BASE64_PART}@${SERVER_IP}:${PORT}"
fi

# Tạo QR code
QRCODE_PATH="$WORK_DIR/ss_qrcode.png"
qrencode -s 8 -o "$QRCODE_PATH" "$SS_URI"

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
echo "Để kiểm tra trạng thái: systemctl status singbox"
echo "Để xem logs: journalctl -u singbox -f"
echo
echo "Cấu hình SingBox được lưu tại: $WORK_DIR/config.json"
echo

# Kiểm tra cài đặt tường lửa và mở cổng
echo "===== Kiểm tra và cấu hình tường lửa ====="
# Kiểm tra và mở cổng với UFW nếu đang chạy
if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
  echo "UFW đang hoạt động, mở cổng $PORT..."
  ufw allow $PORT/tcp
  ufw allow $PORT/udp
  echo "Đã mở cổng $PORT trên UFW firewall"
fi

# Kiểm tra và mở cổng với iptables
if command -v iptables &> /dev/null; then
  echo "Mở cổng $PORT trên iptables..."
  iptables -I INPUT -p tcp --dport $PORT -j ACCEPT
  iptables -I INPUT -p udp --dport $PORT -j ACCEPT
  echo "Đã mở cổng $PORT trên iptables"
  
  # Lưu cấu hình iptables nếu có iptables-save
  if command -v iptables-save &> /dev/null; then
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || iptables-save > /etc/iptables.rules 2>/dev/null || echo "Không thể lưu quy tắc iptables"
  fi
fi

# Hiển thị thông tin QR code
echo "Đã tạo QR code tại: $QRCODE_PATH"
echo
echo "Để xem QR code trên terminal (nếu muốn):"
echo "apt install -y fbi"
echo "fbi $QRCODE_PATH"
echo
echo "Hoặc copy file QR code về máy của bạn bằng lệnh:"
echo "scp user@${SERVER_IP}:$QRCODE_PATH /đường/dẫn/cục/bộ"
