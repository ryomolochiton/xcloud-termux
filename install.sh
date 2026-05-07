#!/data/data/com.termux/files/usr/bin/bash
echo "🚀 ==================================="
echo "   XCloud Auto Renew v4.3 + Auto Login"
echo "🚀 ==================================="

# Cài đặt cơ bản
pkg update -y &>/dev/null
pkg install nodejs git screen -y

# Clone repo
cd ~ && rm -rf xcloud-termux
git clone https://github.com/ryomolochiton/xcloud-termux.git
cd xcloud-termux

# Cài npm
echo "📦 Cài đặt packages..."
npm install &>/dev/null

echo ""
echo "✅ Cài đặt HOÀN THÀNH!"
echo "====================================="
echo ""

# 🎯 BƯỚC 1: NHẬP TÀI KHOẢN/MẬT KHẨU
echo "🔐 BƯỚC 1: NHẬP TÀI KHOẢN XCloud"
read -p "Username (VD: hacchaylo): " USERNAME
read -s -p "Password: " PASSWORD
echo ""

# Tạo .env
cat > .env << EOF
USERNAME=$USERNAME
PASSWORD=$PASSWORD
EOF

echo "✅ Đã lưu: $USERNAME"
echo "🔐 Mật khẩu đã ẩn an toàn (.env)"

echo ""
echo "====================================="
echo "🔧 BƯỚC 2: TEST LOGIN"
echo "npm run login"
echo ""
echo "🚀 BƯỚC 3: CHẠY 24/7"
echo "screen -dmS xcloud npm run full"
echo "screen -r xcloud"
echo ""
echo "📱 XEM LOG: screen -r xcloud"
echo "🛑 DỪNG: screen -S xcloud -X quit"
echo "====================================="
echo "🎉 SẴN SÀNG! Chạy: npm run full"
