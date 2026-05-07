#!/usr/bin/env node
require('dotenv').config();
const axios = require('axios');
const { CookieJar } = require('tough-cookie');
const fs = require('fs');
const cheerio = require('cheerio');

const USERNAME = process.env.USERNAME || 'accbloxmamgo@gmail.com';
const PASSWORD = process.env.PASSWORD || '@quangthanh2008';

console.log('👤 Login:', USERNAME);
console.log('🔐 Auto Login SUPER v3.0...');

async function autoLogin() {
    const jar = new CookieJar();
    const client = axios.create({ 
        jar, 
        timeout: 20000,
        headers: { 
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml,*/*;q=0.9',
            'Accept-Language': 'en-US,en;q=0.9,vi;q=0.8',
            'Sec-Fetch-Site': 'none',
            'Sec-Fetch-Mode': 'navigate',
            'Sec-Fetch-Dest': 'document'
        }
    });
    
    try {
        // 1. HOME PAGE - Multiple CSRF methods
        console.log('🌐 Step 1/5: Trang chủ...');
        let home = await client.get('https://app.xcloudphone.com/');
        let $ = cheerio.load(home.data);
        
        // Method 1: input field
        let csrf = $('input[name="csrfmiddlewaretoken"]').val() ||
                  $('input[name="csrf_token"]').val() ||
                  $('[name="csrfmiddlewaretoken"]').val();
        
        // Method 2: meta tag
        if (!csrf) csrf = $('meta[name="csrf-token"]').attr('content') ||
                          $('meta[name="csrf"]').attr('content');
        
        // Method 3: script variable
        if (!csrf) {
            const scripts = home.data.match(/csrfmiddlewaretoken\s*[:=]\s*["']([^"']+)["']/gi);
            if (scripts) csrf = scripts[0].match(/["']([^"']+)["']$/)[1];
        }
        
        // Method 4: regex brute force
        if (!csrf) {
            const matches = home.data.match(/csrf[^a-zA-Z0-9]{0,10}["':]\s*["']([a-f0-9]{64})/i);
            csrf = matches ? matches[1] : null;
        }
        
        if (!csrf) throw new Error('CSRF không tìm thấy');
        console.log('✅ CSRF:', csrf.slice(0, 16) + '...');
        
        // 2. LOGIN PAGE (nếu cần)
        console.log('🔑 Step 2/5: Login page...');
        home = await client.get('https://app.xcloudphone.com/user/login/');
        $ = cheerio.load(home.data);
        csrf = $('input[name="csrfmiddlewaretoken"]').val() || csrf;
        
        // 3. LOGIN POST
        console.log('📤 Step 3/5: Submit login...');
        const formData = new URLSearchParams({
            'username': USERNAME,
            'password': PASSWORD,
            'csrfmiddlewaretoken': csrf
        });
        
        const login = await client.post('https://app.xcloudphone.com/user/login/', 
            formData, {
                headers: {
                    'Content-Type': 'application/x-www-form-urlencoded',
                    'X-CSRFToken': csrf,
                    'X-Requested-With': 'XMLHttpRequest',
                    'Referer': 'https://app.xcloudphone.com/user/login/'
                },
                maxRedirects: 5,
                validateStatus: () => true
            });
        
        console.log('📥 Login status:', login.status);
        if (login.status !== 200 && login.status !== 302) {
            throw new Error(`Login fail ${login.status}`);
        }
        
        // 4. VERIFY API
        console.log('🔍 Step 4/5: Test API...');
        const api = await client.get('https://api.xcloudphone.com/renters/rental-sessions?page=1&limit=5');
        console.log('✅ API:', api.status, api.data.data?.length || 0, 'thiết bị');
        
        if (api.status !== 200) throw new Error('API unauthorized');
        
        // 5. SAVE COOKIES
        console.log('💾 Step 5/5: Lưu cookies...');
        const cookiesStr = jar.getCookieStringSync('https://app.xcloudphone.com');
        const cookies = {};
        cookiesStr.split(';').forEach(c => {
            const [k, v] = c.trim().split('=', 2);
            if (k) cookies[k] = v || '';
        });
        
        fs.writeFileSync('cookies.json', JSON.stringify(cookies, null, 2));
        console.log('🎉 LOGIN HOÀN THÀNH!');
        console.log('📱 Thiết bị:', api.data.data?.map(d => d.sessionName).join(', ') || 'Không có');
        
    } catch (error) {
        console.error('💥 LỖI:', error.message);
        if (error.response) {
            console.error('Status:', error.response.status);
            console.error('Data:', error.response.data?.toString().slice(0, 300));
        }
    }
}

autoLogin();
