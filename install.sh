#!/data/data/com.termux/files/usr/bin/bash
echo "🚀 XCloud Auto Renew v4.3 - 1 Click Install"
pkg update -y && pkg upgrade -y
pkg install nodejs git screen curl -y
cd ~ && git clone https://github.com/YOUR_USERNAME/xcloud-termux.git && cd xcloud-termux
npm install
echo '{"sessionid":"","csrftoken":"","auth_token":""}' > cookies.json
cat > start.sh << 'S'
cd ~/xcloud-termux && screen -dmS xcloud npm start && echo "✅ Chạy rồi! Log: screen -r xcloud"
S
chmod +x start.sh
echo "🎉 XONG! Chạy: cd ~/xcloud-termux && ./start.sh"
echo "📱 Log: screen -r xcloud"
echo "🍪 Cookies: nano cookies.json"
