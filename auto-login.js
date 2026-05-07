#!/usr/bin/env node
require('dotenv').config();
const axios = require('axios');
const { CookieJar } = require('tough-cookie');
const fs = require('fs');
const cheerio = require('cheerio');

const USERNAME = process.env.USERNAME || 'accbloxmamgo@gmail.com';
const PASSWORD = process.env.PASSWORD || '@quangthanh2008';

if (!USERNAME || !PASSWORD) {
    console.error('❌ Thiếu USERNAME/PASSWORD trong .env');
    process.exit(1);
}

async function autoLogin() {
    console.log('🔐 Auto Login XCloudPhone v2.0...');
    const jar = new CookieJar();
    const client = axios.create({ 
        jar, 
        timeout: 15000,
        headers: { 
            'User-Agent': 'Mozilla/5.0 (Linux; Android 10; SM-G973F) AppleWebKit/537.36',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'vi-VN,vi;q=0.9,en;q=0.8',
            'Referer': 'https://app.xcloudphone.com/'
        }
    });
    
    try {
        // 1. Trang chủ
        console.log('📱 Truy cập trang chủ...');
        const home = await client.get('https://app.xcloudphone.com/');
        const $home = cheerio.load(home.data);
        
        // Tìm CSRF nhiều cách
        let csrfToken = $home('input[name="csrfmiddlewaretoken"]').val() ||
                       $home('meta[name="csrf-token"]').attr('content') ||
                       home.data.match(/csrfmiddlewaretoken["']\s*:\s*["']([^"']+)["']/i)?.[1];
        
        if (!csrfToken) {
            // Fallback: regex mạnh hơn
            const csrfMatches = home.data.match(/csrfmiddlewaretoken\s*["']\s*([^"']+)/gi);
            csrfToken = csrfMatches ? csrfMatches[0].match(/[^"']+$/)[0] : null;
        }
        
        if (!csrfToken) throw new Error('❌ Không tìm CSRF token');
        console.log('✅ CSRF:', csrfToken.slice(0, 20) + '...');
        
        // 2. Login POST
        console.log('🔑 Đang login...');
        const loginData = new URLSearchParams({
            username: USERNAME,
            password: PASSWORD,
            csrfmiddlewaretoken: csrfToken
        });
        
        const loginRes = await client.post('https://app.xcloudphone.com/user/login/', 
            loginData.toString(), {
                headers: {
                    'Content-Type': 'application/x-www-form-urlencoded',
                    'X-CSRFToken': csrfToken,
                    'X-Requested-With': 'XMLHttpRequest',
                    'Referer': 'https://app.xcloudphone.com/user/login/'
                },
                maxRedirects: 3
            });
        
        console.log('✅ Login response:', loginRes.status);
        
        // 3. Test API
        console.log('🧪 Test API...');
        const sessions = await client.get('https://api.xcloudphone.com/renters/rental-sessions?page=1&limit=5');
        console.log('✅ API OK!', sessions.data.data?.length || 0, 'thiết bị');
        
        // 4. Lưu cookies
        const cookies = jar.getCookieStringSync('https://app.xcloudphone.com');
        const cookieObj = cookies.split('; ').reduce((acc, c) => {
            const eqIndex = c.indexOf('=');
            const key = c.slice(0, eqIndex).trim();
            const value = c.slice(eqIndex + 1).trim();
            if (key) acc[key] = value;
            return acc;
        }, {});
        
        fs.writeFileSync('cookies.json', JSON.stringify(cookieObj, null, 2));
        console.log('💾 Cookies.json lưu OK');
        console.log('🎉 LOGIN HOÀN THÀNH!');
        
    } catch (error) {
        console.error('❌ LỖI:', error.message);
        console.error('Debug:', error.response?.status, error.response?.data?.slice(0, 200));
    }
}

autoLogin();
