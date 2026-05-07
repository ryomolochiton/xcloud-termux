#!/data/data/com.termux/files/usr/bin/bash
echo "🚀 XCloud Auto Renew v4.3 + Auto Login"

# Cài base
pkg update -y && pkg install nodejs git screen -y

# Clone repo
cd ~ && rm -rf xcloud-termux && git clone https://github.com/ryomolochiton/xcloud-termux.git && cd xcloud-termux

# Cài npm
npm install

# Tạo .env config
cat > .env << 'EOF'
USERNAME=YOUR_USERNAME
PASSWORD=YOUR_PASSWORD
EOF

echo "📝 ✅ Cài xong!"
echo "🔧 SỬA .env:"
echo "  nano .env"
echo "  USERNAME=hacchaylo"
echo "  PASSWORD=matkhau123"
echo ""
echo "🚀 CHẠY:"
echo "  npm run login   # Tự login"
echo "  npm run full    # Login + Renew"
echo "  npm start       # Chỉ renew"
echo ""
echo "📱 BACKGROUND:"
echo "  screen -dmS xcloud npm run full"
echo "  screen -r xcloud"
