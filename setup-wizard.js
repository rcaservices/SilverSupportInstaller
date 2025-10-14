const express = require('express');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { exec } = require('child_process');
const app = express();
const PORT = 9443;

app.use(express.json());
app.use(express.urlencoded({ extended: true }));

const sessions = new Map();
const SILVER_ROOT = '/usr/local/silver';
const SILVER_ETC = '/etc/silver';
const ENV_FILE = path.join(SILVER_ROOT, '.env');
const ADMIN_FILE = path.join(SILVER_ETC, 'admin.json');
const SETUP_LOCK = path.join(SILVER_ETC, 'setup.lock');

const isSetupComplete = () => fs.existsSync(SETUP_LOCK);
const hashPassword = (p) => crypto.createHash('sha256').update(p).digest('hex');
const generateSessionId = () => crypto.randomBytes(32).toString('hex');
const checkSession = (req) => {
  const sid = req.headers['x-session-id'] || req.query.session;
  return sessions.has(sid);
};

app.get('/', (req, res) => {
  if (!isSetupComplete()) {
    res.send(getSetupHTML());
  } else {
    res.send(getLoginHTML());
  }
});

app.post('/setup', async (req, res) => {
  if (isSetupComplete()) return res.status(403).json({ error: 'Setup complete' });
  try {
    const cfg = req.body;
    let env = fs.readFileSync(ENV_FILE, 'utf8');
    for (const [k, v] of Object.entries(cfg)) {
      if (k !== 'adminUsername' && k !== 'adminPassword') {
        const re = new RegExp('^' + k + '=.*$', 'm');
        env = re.test(env) ? env.replace(re, k + '=' + v) : env + '\n' + k + '=' + v;
      }
    }
    fs.writeFileSync(ENV_FILE, env);
    fs.writeFileSync(ADMIN_FILE, JSON.stringify({
      username: cfg.adminUsername,
      passwordHash: hashPassword(cfg.adminPassword),
      createdAt: new Date().toISOString()
    }, null, 2));
    fs.writeFileSync(SETUP_LOCK, new Date().toISOString());
    exec('cd /usr/local/silver && pm2 restart all', (err) => { if (err) console.error(err); });
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.post('/login', (req, res) => {
  if (!isSetupComplete()) return res.status(400).json({ error: 'Setup not complete' });
  try {
    const { username, password } = req.body;
    const admin = JSON.parse(fs.readFileSync(ADMIN_FILE, 'utf8'));
    if (username === admin.username && hashPassword(password) === admin.passwordHash) {
      const sid = generateSessionId();
      sessions.set(sid, { username, loginTime: Date.now() });
      res.json({ success: true, sessionId: sid });
    } else {
      res.status(401).json({ error: 'Invalid credentials' });
    }
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/dashboard', (req, res) => {
  if (!checkSession(req)) return res.status(401).send('Unauthorized');
  res.send(getDashboardHTML());
});

app.get('/api/config', (req, res) => {
  if (!checkSession(req)) return res.status(401).json({ error: 'Unauthorized' });
  try {
    const env = fs.readFileSync(ENV_FILE, 'utf8');
    const cfg = {};
    env.split('\n').forEach(line => {
      if (line && !line.startsWith('#') && line.includes('=')) {
        const [k, ...v] = line.split('=');
        cfg[k.trim()] = v.join('=').trim();
      }
    });
    res.json({ config: cfg });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.post('/api/config', (req, res) => {
  if (!checkSession(req)) return res.status(401).json({ error: 'Unauthorized' });
  try {
    const updates = req.body;
    let env = fs.readFileSync(ENV_FILE, 'utf8');
    for (const [k, v] of Object.entries(updates)) {
      const re = new RegExp('^' + k + '=.*$', 'm');
      env = re.test(env) ? env.replace(re, k + '=' + v) : env + '\n' + k + '=' + v;
    }
    fs.writeFileSync(ENV_FILE, env);
    exec('cd /usr/local/silver && pm2 restart all', (err) => { if (err) console.error(err); });
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

function getSetupHTML() {
  return '<!DOCTYPE html><html><head><title>SilverSupport Setup</title><style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:Arial,sans-serif;background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);min-height:100vh;padding:20px}.container{max-width:800px;margin:0 auto;background:#fff;border-radius:12px;box-shadow:0 20px 60px rgba(0,0,0,.3)}.header{background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);color:#fff;padding:40px;text-align:center;border-radius:12px 12px 0 0}.content{padding:40px}.form-group{margin-bottom:20px}label{display:block;font-weight:600;margin-bottom:8px}input{width:100%;padding:12px;border:2px solid #e0e0e0;border-radius:6px;font-size:14px}.section-title{font-size:18px;font-weight:600;margin:30px 0 20px;color:#667eea}button{background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);color:#fff;border:none;padding:15px;font-size:16px;font-weight:600;border-radius:6px;cursor:pointer;width:100%;margin-top:20px}.help-text{font-size:12px;color:#666;margin-top:5px}</style></head><body><div class="container"><div class="header"><h1>🎉 SilverSupport Setup</h1><p>Initial Configuration</p></div><div class="content"><form id="form"><div class="section-title">👤 Admin Account</div><div class="form-group"><label>Username</label><input name="adminUsername" required><div class="help-text">Administrator username</div></div><div class="form-group"><label>Password</label><input type="password" name="adminPassword" required minlength="8"><div class="help-text">Minimum 8 characters</div></div><div class="section-title">📞 Twilio</div><div class="form-group"><label>Account SID</label><input name="TWILIO_ACCOUNT_SID" required></div><div class="form-group"><label>Auth Token</label><input type="password" name="TWILIO_AUTH_TOKEN" required></div><div class="form-group"><label>Phone Number</label><input name="TWILIO_PHONE_NUMBER" required></div><div class="section-title">🤖 AI Services</div><div class="form-group"><label>OpenAI</label><input type="password" name="OPENAI_API_KEY" required></div><div class="form-group"><label>Anthropic</label><input type="password" name="ANTHROPIC_API_KEY" required></div><div class="section-title">🌐 Domain</div><div class="form-group"><label>Domain</label><input name="DOMAIN" required value="alpha.silverzupport.us"></div><button type="submit">Complete Setup</button></form><div id="msg" style="margin-top:20px;padding:15px;border-radius:6px;display:none"></div></div></div><script>document.getElementById("form").onsubmit=async e=>{e.preventDefault();const data={};new FormData(e.target).forEach((v,k)=>data[k]=v);try{const r=await fetch("/setup",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(data)});const j=await r.json();const msg=document.getElementById("msg");if(r.ok){msg.style.background="#d4edda";msg.style.color="#155724";msg.innerHTML="✅ Complete! Redirecting...";msg.style.display="block";setTimeout(()=>location.href="/",2e3)}else throw new Error(j.error)}catch(err){const msg=document.getElementById("msg");msg.style.background="#f8d7da";msg.style.color="#721c24";msg.innerHTML="❌ Error: "+err.message;msg.style.display="block"}}</script></body></html>';
}

function getLoginHTML() {
  return '<!DOCTYPE html><html><head><title>Admin Login</title><style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:Arial,sans-serif;background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);min-height:100vh;display:flex;align-items:center;justify-content:center;padding:20px}.container{max-width:450px;width:100%;background:#fff;border-radius:12px;box-shadow:0 20px 60px rgba(0,0,0,.3)}.header{background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);color:#fff;padding:50px 40px;text-align:center;border-radius:12px 12px 0 0}.content{padding:40px}.form-group{margin-bottom:25px}label{display:block;font-weight:600;margin-bottom:8px}input{width:100%;padding:14px;border:2px solid #e0e0e0;border-radius:6px;font-size:14px}button{background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);color:#fff;border:none;padding:16px;font-size:16px;font-weight:600;border-radius:6px;cursor:pointer;width:100%}</style></head><body><div class="container"><div class="header"><h1>🔐 Admin Login</h1></div><div class="content"><form id="form"><div class="form-group"><label>Username</label><input name="username" required autofocus></div><div class="form-group"><label>Password</label><input type="password" name="password" required></div><button type="submit">Sign In</button></form><div id="error" style="margin-top:20px;padding:12px;background:#f8d7da;color:#721c24;border-radius:6px;display:none"></div></div></div><script>document.getElementById("form").onsubmit=async e=>{e.preventDefault();const data={};new FormData(e.target).forEach((v,k)=>data[k]=v);try{const r=await fetch("/login",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(data)});const j=await r.json();if(r.ok){sessionStorage.setItem("sessionId",j.sessionId);location.href="/dashboard?session="+j.sessionId}else{document.getElementById("error").textContent=j.error;document.getElementById("error").style.display="block"}}catch(err){document.getElementById("error").textContent="Connection error";document.getElementById("error").style.display="block"}}</script></body></html>';
}

function getDashboardHTML() {
  return '<!DOCTYPE html><html><head><title>Admin Dashboard</title><style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:Arial,sans-serif;background:#f5f7fa}.header{background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);color:#fff;padding:20px 40px;display:flex;justify-content:space-between;align-items:center}.logout{background:rgba(255,255,255,.2);color:#fff;border:none;padding:10px 20px;border-radius:6px;cursor:pointer}.container{max-width:1400px;margin:0 auto;padding:40px 20px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:25px}.card{background:#fff;border-radius:12px;padding:30px;box-shadow:0 2px 8px rgba(0,0,0,.1);cursor:pointer;text-align:center;transition:all .3s}.card:hover{transform:translateY(-5px);box-shadow:0 8px 25px rgba(102,126,234,.3)}.icon{font-size:48px;margin-bottom:15px}.title{font-size:20px;font-weight:600;margin-bottom:8px}.section{background:#fff;border-radius:12px;padding:30px;box-shadow:0 2px 8px rgba(0,0,0,.1);margin-top:30px;display:none}.section.active{display:block}.form-group{margin-bottom:20px}label{display:block;font-weight:600;margin-bottom:8px}input{width:100%;padding:12px;border:2px solid #e0e0e0;border-radius:6px;font-size:14px}button{background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);color:#fff;border:none;padding:14px 30px;border-radius:6px;cursor:pointer;font-size:16px;font-weight:600;margin-top:10px}</style></head><body><div class="header"><h1>🎛️ Admin Dashboard</h1><button class="logout" onclick="logout()">Logout</button></div><div class="container"><div id="dash"><div class="grid"><div class="card" onclick="showSection(\'api\')"><div class="icon">🔑</div><div class="title">API Keys</div></div><div class="card" onclick="showSection(\'system\')"><div class="icon">⚙️</div><div class="title">System</div></div><div class="card" onclick="showSection(\'db\')"><div class="icon">🗄️</div><div class="title">Database</div></div></div></div><div id="apiSection" class="section"><h2>API Keys</h2><button onclick="showDash()">← Back</button><form id="apiForm" style="margin-top:20px"><div class="form-group"><label>Twilio SID</label><input name="TWILIO_ACCOUNT_SID" id="tsid"></div><div class="form-group"><label>Twilio Token</label><input type="password" name="TWILIO_AUTH_TOKEN" id="ttoken"></div><div class="form-group"><label>Twilio Phone</label><input name="TWILIO_PHONE_NUMBER" id="tphone"></div><div class="form-group"><label>OpenAI Key</label><input type="password" name="OPENAI_API_KEY" id="oai"></div><div class="form-group"><label>Anthropic Key</label><input type="password" name="ANTHROPIC_API_KEY" id="anth"></div><button type="submit">Save</button></form><div id="apiMsg" style="margin-top:15px;padding:12px;border-radius:6px;display:none"></div></div><div id="systemSection" class="section"><h2>System Settings</h2><button onclick="showDash()">← Back</button><form id="sysForm" style="margin-top:20px"><div class="form-group"><label>Domain</label><input name="DOMAIN" id="domain"></div><div class="form-group"><label>Environment</label><input name="NODE_ENV" id="env"></div><div class="form-group"><label>Port</label><input name="PORT" id="port" type="number"></div><button type="submit">Save</button></form><div id="sysMsg" style="margin-top:15px;padding:12px;border-radius:6px;display:none"></div></div><div id="dbSection" class="section"><h2>Database</h2><button onclick="showDash()">← Back</button><form id="dbForm" style="margin-top:20px"><div class="form-group"><label>Database URL</label><input name="DATABASE_URL" id="dburl"></div><button type="submit">Save</button></form><div id="dbMsg" style="margin-top:15px;padding:12px;border-radius:6px;display:none"></div></div></div><script>const sid=sessionStorage.getItem("sessionId");if(!sid)location.href="/";async function api(url,opts={}){opts.headers={...opts.headers,"X-Session-Id":sid};const r=await fetch(url,opts);if(r.status===401)location.href="/";return r}async function loadCfg(){const r=await api("/api/config");const{config}=await r.json();Object.keys(config).forEach(k=>{const el=document.getElementById(k.toLowerCase());if(el)el.value=config[k]})}function showSection(s){document.getElementById("dash").style.display="none";document.querySelectorAll(".section").forEach(x=>x.classList.remove("active"));document.getElementById(s+"Section").classList.add("active");loadCfg()}function showDash(){document.getElementById("dash").style.display="block";document.querySelectorAll(".section").forEach(x=>x.classList.remove("active"))}document.getElementById("apiForm").onsubmit=async e=>{e.preventDefault();const data={};new FormData(e.target).forEach((v,k)=>data[k]=v);const r=await api("/api/config",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(data)});const msg=document.getElementById("apiMsg");msg.textContent=r.ok?"✅ Saved!":"❌ Failed";msg.style.background=r.ok?"#d4edda":"#f8d7da";msg.style.color=r.ok?"#155724":"#721c24";msg.style.display="block"};document.getElementById("sysForm").onsubmit=async e=>{e.preventDefault();const data={};new FormData(e.target).forEach((v,k)=>data[k]=v);const r=await api("/api/config",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(data)});const msg=document.getElementById("sysMsg");msg.textContent=r.ok?"✅ Saved!":"❌ Failed";msg.style.background=r.ok?"#d4edda":"#f8d7da";msg.style.color=r.ok?"#155724":"#721c24";msg.style.display="block"};document.getElementById("dbForm").onsubmit=async e=>{e.preventDefault();const data={};new FormData(e.target).forEach((v,k)=>data[k]=v);const r=await api("/api/config",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(data)});const msg=document.getElementById("dbMsg");msg.textContent=r.ok?"✅ Saved!":"❌ Failed";msg.style.background=r.ok?"#d4edda":"#f8d7da";msg.style.color=r.ok?"#155724":"#721c24";msg.style.display="block"};function logout(){sessionStorage.removeItem("sessionId");location.href="/"}</script></body></html>';
}

app.listen(PORT, '0.0.0.0', () => {
  console.log('Admin dashboard running on port ' + PORT);
});
