const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const { spawn } = require('child_process');
const net = require('net');
const fs = require('fs');
const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');

const JWT_SECRET = 'secredo_super_seguro_jukebox_2025'; // Em prod, use variavel de ambiente

// --- SETUP MONGODB ---
mongoose.connect('mongodb://127.0.0.1:27017/jukebox')
    .then(() => console.log('🔥 MongoDB Conectado!'))
    .catch(err => console.error('Erro no Mongo:', err));

// --- SCHEMAS ---
const UserSchema = new mongoose.Schema({
    username: { type: String, unique: true, required: true },
    password: { type: String, required: true },
    name: String,
    lastname: String,
    role: { type: String, default: 'user' }, // 'admin' ou 'user'
    createdAt: { type: Date, default: Date.now }
});
const UserModel = mongoose.model('User', UserSchema);

const QueueSchema = new mongoose.Schema({
    title: String, url: String, thumbnail: String,
    addedBy: String, // Nome de quem adicionou
    addedByUsername: String,
    createdAt: { type: Date, default: Date.now }
});
const QueueModel = mongoose.model('Queue', QueueSchema);

const HistorySchema = new mongoose.Schema({
    title: String, url: String, thumbnail: String,
    requestedBy: String, // Nome de quem pediu
    playedAt: { type: Date, default: Date.now }
});
const HistoryModel = mongoose.model('History', HistorySchema);

const SettingsSchema = new mongoose.Schema({
    key: { type: String, unique: true },
    value: mongoose.Schema.Types.Mixed
});
const SettingsModel = mongoose.model('Settings', SettingsSchema);

// --- SETUP SERVIDOR ---
const app = express();
const server = http.createServer(app);
const io = new Server(server);
const PORT = 3000;
const MPV_SOCKET = '/tmp/mpvsocket';

let currentSong = null;
let playerState = { paused: false, volume: 100, position: 0, duration: 0, isLoading: false };
let mpvClient = null;

app.use(express.static(__dirname + '/public'));
app.use(express.json());

// --- ROTAS DE AUTENTICAÇÃO (API) ---

// 1. Checa se o sistema precisa de Setup (se não tem nenhum usuário)
app.get('/api/auth/check-init', async (req, res) => {
    const count = await UserModel.countDocuments();
    res.json({ needsSetup: count === 0 });
});

// 2. Setup Inicial (Cria o Admin)
app.post('/api/auth/setup', async (req, res) => {
    const count = await UserModel.countDocuments();
    if (count > 0) return res.status(403).json({ error: 'Sistema já configurado.' });

    const { username, password, name, lastname } = req.body;
    const hashedPassword = await bcrypt.hash(password, 10);

    const user = await UserModel.create({
        username, password: hashedPassword, name, lastname, role: 'admin'
    });

    const token = jwt.sign({ id: user._id, role: user.role, name: user.name }, JWT_SECRET);
    res.json({ token, user: { name: user.name, role: user.role } });
});

// 3. Login
app.post('/api/auth/login', async (req, res) => {
    const { username, password } = req.body;
    const user = await UserModel.findOne({ username });
    if (!user) return res.status(400).json({ error: 'Usuário não encontrado' });

    const valid = await bcrypt.compare(password, user.password);
    if (!valid) return res.status(400).json({ error: 'Senha incorreta' });

    const token = jwt.sign({ id: user._id, role: user.role, name: user.name }, JWT_SECRET);
    res.json({ token, user: { name: user.name, role: user.role } });
});

// 4. Criar Usuário (Apenas Admin - Middleware manual aqui pra simplificar)
app.post('/api/auth/register', async (req, res) => {
    const token = req.headers.authorization?.split(' ')[1];
    if (!token) return res.status(401).json({ error: 'Sem token' });

    try {
        const decoded = jwt.verify(token, JWT_SECRET);
        if (decoded.role !== 'admin') return res.status(403).json({ error: 'Apenas admins podem criar usuários' });

        const { username, password, name, lastname } = req.body;
        const hashedPassword = await bcrypt.hash(password, 10);
        
        await UserModel.create({ username, password: hashedPassword, name, lastname, role: 'user' });
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// --- MIDDLEWARE SOCKET.IO (Segurança) ---
io.use((socket, next) => {
    const token = socket.handshake.auth.token;
    if (!token) return next(new Error("Não autorizado"));

    jwt.verify(token, JWT_SECRET, (err, decoded) => {
        if (err) return next(new Error("Token inválido"));
        socket.user = decoded; // Guarda dados do user no socket
        next();
    });
});

// --- PLAYER LOGIC (Mesma de antes + resetPlayerState) ---
function resetPlayerState() {
    playerState.position = 0; playerState.duration = 0; playerState.isLoading = true;
    io.emit('playerState', playerState);
}

async function startMpv() {
    if (fs.existsSync(MPV_SOCKET)) fs.unlinkSync(MPV_SOCKET);
    const savedVol = await SettingsModel.findOne({ key: 'volume' });
    const initialVol = savedVol ? savedVol.value : 100;
    playerState.volume = initialVol;

    const mpvProcess = spawn('mpv', [
        '--idle', '--no-video', '--force-window=no', 
        `--input-ipc-server=${MPV_SOCKET}`, `--volume=${initialVol}`
    ]);
    mpvProcess.on('close', () => setTimeout(startMpv, 1000));
    setTimeout(connectToMpvSocket, 2000);
}

function connectToMpvSocket() {
    mpvClient = net.createConnection({ path: MPV_SOCKET });
    mpvClient.on('data', (data) => {
        const lines = data.toString().split('\n');
        lines.forEach(line => {
            if (!line) return;
            try {
                const msg = JSON.parse(line);
                if (msg.event === 'property-change') {
                    if (msg.name === 'time-pos') { playerState.position = msg.data; playerState.isLoading = false; }
                    if (msg.name === 'duration') playerState.duration = msg.data;
                    if (msg.name === 'volume') playerState.volume = msg.data;
                    if (msg.name === 'pause') playerState.paused = msg.data;
                    if (msg.name === 'idle-active' && msg.data === true) {
                        currentSong = null; resetPlayerState(); playNext();
                    }
                    io.emit('playerState', playerState);
                }
            } catch (e) {}
        });
    });
    mpvClient.on('error', () => setTimeout(connectToMpvSocket, 1000));
    setupObservers();
    sendMpvCommand(['set_property', 'volume', playerState.volume]);
}

function sendMpvCommand(command) {
    if (mpvClient && !mpvClient.destroyed) mpvClient.write(JSON.stringify({ command: command }) + '\n');
}

function setupObservers() {
    ['time-pos', 'volume', 'pause', 'duration', 'idle-active'].forEach((p, i) => 
        sendMpvCommand(['observe_property', i + 1, p])
    );
}

setInterval(() => {
    if (!mpvClient || mpvClient.destroyed) return;
    sendMpvCommand(['get_property', 'time-pos']);
}, 2000);

// --- JUKEBOX FUNCTIONS ---
async function getYoutubeData(url) {
    return new Promise((resolve) => {
        const proc = spawn('yt-dlp', ['-J', '--flat-playlist', url]);
        let data = '';
        proc.stdout.on('data', d => data += d);
        proc.on('close', () => {
            try {
                const json = JSON.parse(data);
                resolve({
                    title: json.title || 'Desconhecido',
                    thumbnail: json.thumbnail || json.thumbnails?.[0]?.url || null
                });
            } catch (e) { resolve({ title: url, thumbnail: null }); }
        });
    });
}

async function searchYoutube(query) {
    console.log(`🔎 Buscando: "${query}"`);
    return new Promise((resolve) => {
        const proc = spawn('yt-dlp', [`ytsearch10:${query}`, '--flat-playlist', '--dump-json']);
        let rawData = '';
        proc.stdout.on('data', d => rawData += d);
        proc.on('close', () => {
            const results = [];
            const lines = rawData.split('\n');
            lines.forEach(line => {
                if(!line) return;
                try {
                    const json = JSON.parse(line);
                    if (json.id && json.title) {
                        results.push({
                            title: json.title,
                            url: `https://www.youtube.com/watch?v=${json.id}`,
                            thumbnail: `https://i.ytimg.com/vi/${json.id}/mqdefault.jpg`
                        });
                    }
                } catch (e) {}
            });
            resolve(results);
        });
    });
}

async function playNext() {
    if (currentSong) return;
    const nextTrack = await QueueModel.findOne().sort({ createdAt: 1 });
    if (!nextTrack) {
        currentSong = null; resetPlayerState();
        io.emit('status', { current: null, queue: [] });
        return;
    }
    await playTrack(nextTrack);
}

async function playTrack(track) {
    currentSong = track; resetPlayerState();
    await QueueModel.deleteOne({ _id: track._id });
    
    // Salva no histórico com o nome de quem pediu
    await HistoryModel.create({ 
        title: currentSong.title, 
        url: currentSong.url, 
        thumbnail: currentSong.thumbnail,
        requestedBy: currentSong.addedBy // <--- Importante
    });

    sendMpvCommand(['loadfile', currentSong.url]);
    sendMpvCommand(['set_property', 'pause', false]);
    broadcastStatus();
}

async function broadcastStatus() {
    const queue = await QueueModel.find().sort({ createdAt: 1 });
    io.emit('status', { current: currentSong, queue });
}

// --- SOCKETS ---
startMpv();

io.on('connection', async (socket) => {
    // O usuário já está autenticado pelo middleware 'io.use'
    // socket.user contém { id, name, role }
    
    broadcastStatus();
    socket.emit('playerState', playerState);
    socket.emit('user_info', socket.user); // Envia infos do usuario pro front

    socket.on('add', async (url) => {
        const data = await getYoutubeData(url);
        await QueueModel.create({ 
            title: data.title, 
            url: url, 
            thumbnail: data.thumbnail,
            addedBy: socket.user.name, // <--- Salva o nome do usuário
            addedByUsername: socket.user.username 
        });
        if (!currentSong) playNext(); else broadcastStatus();
    });

    socket.on('search', async (query) => {
        const results = await searchYoutube(query);
        socket.emit('search_results', results);
    });

    socket.on('jump_to', async (id) => {
        const track = await QueueModel.findById(id);
        if (track) await playTrack(track);
    });

    socket.on('replay_history', async (id) => {
        const historyItem = await HistoryModel.findById(id);
        if (historyItem) {
            await QueueModel.create({ 
                title: historyItem.title, 
                url: historyItem.url, 
                thumbnail: historyItem.thumbnail,
                addedBy: socket.user.name // Re-adicionado por quem clicou no replay
            });
            if (!currentSong) playNext(); else broadcastStatus();
        }
    });

    socket.on('get_history', async () => {
        const history = await HistoryModel.find().sort({ playedAt: -1 }).limit(50);
        socket.emit('history_data', history);
    });

    socket.on('control', async (action) => {
        switch (action.type) {
            case 'pause': sendMpvCommand(['cycle', 'pause']); break;
            case 'next': currentSong = null; resetPlayerState(); playNext(); break;
            case 'prev': sendMpvCommand(['seek', 0, 'absolute']); break;
            case 'seek': sendMpvCommand(['seek', action.value, 'absolute']); break;
            case 'set_volume': 
                sendMpvCommand(['set_property', 'volume', action.value]);
                await SettingsModel.findOneAndUpdate({ key: 'volume' }, { value: action.value }, { upsert: true });
                break;
        }
    });
});

server.listen(PORT, () => {
    console.log(`🎵 Jukebox rodando em http://localhost:${PORT}`);
});