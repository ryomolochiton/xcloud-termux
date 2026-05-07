#!/usr/bin/env node
require('dotenv').config();
const axios = require('axios');
const { CookieJar } = require('tough-cookie');
const fs = require('fs');

const USERNAME = process.env.USERNAME || 'hacchaylo';
const PASSWORD = process.env.PASSWORD || '';

if (!USERNAME || !PASSWORD) {
    console.error('❌ Thiếu USERNAME/PASSWORD trong .env');
    process.exit(1);
}

async function autoLogin() {
    console.log('🔐 Auto Login XCloudPhone...');
    const jar = new CookieJar();
    const client = axios.create({ 
        jar, 
        withCredentials: true,
        timeout: 10000,
        headers: { 'User-Agent': 'Mozilla/5.0 (Linux; Android)' }
    });
    
    try {
        // 1. Trang chủ lấy CSRF
        const home = await client.get('https://app.xcloudphone.com/');
        const csrfMatch = home.data.match(/name="csrfmiddlewaretoken"\s+value="([^"]+)"/);
        if (!csrfMatch) throw new Error('Không tìm CSRF token');
        
        const csrfToken = csrfMatch[1];
        console.log('✅ CSRF:', csrfToken.slice(0,20)+'...');
        
        // 2. Login
        const loginData = new URLSearchParams({
            username: USERNAME,
            password: PASSWORD,
            csrfmiddlewaretoken: csrfToken
        });
        
        const loginRes = await client.post('https://app.xcloudphone.com/user/login/', 
            loginData, {
                headers: {
                    'Content-Type': 'application/x-www-form-urlencoded',
                    'X-CSRFToken': csrfToken,
                    'Referer': 'https://app.xcloudphone.com/user/login/'
                }
            });
        
        if (loginRes.status !== 200) throw new Error(`Login fail: ${loginRes.status}`);
        console.log('✅ Login OK!');
        
        // 3. Test API
        const sessions = await client.get('https://api.xcloudphone.com/renters/rental-sessions?page=1&limit=5');
        console.log('✅ API OK!', sessions.data.data?.length || 0, 'thiết bị');
        
        // 4. Lưu cookies
        const cookies = jar.getCookieStringSync('https://app.xcloudphone.com');
        const cookieObj = cookies.split('; ').reduce((acc, c) => {
            const [key, value] = c.split('=', 2);
            if (key && value !== undefined) acc[key.trim()] = value.trim();
            return acc;
        }, {});
        
        fs.writeFileSync('cookies.json', JSON.stringify(cookieObj, null, 2));
        console.log('💾 Lưu cookies.json → Sẵn sàng renew!');
        
    } catch (error) {
        console.error('❌ LỖI:', error.message);
        process.exit(1);
    }
}

autoLogin();
