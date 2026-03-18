require('dotenv').config();

const geoip = require('geoip-lite');
const cors = require('cors');
const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const pool = require('./db');
const keyController = require('./controllers/keyController');
const { generateOTP, sendOTPEmail } = require('./utils/mfa_logic');
const https = require('https');
const fs = require('fs');
const path = require('path');
const socketIo = require('socket.io');
const rateLimit = require('express-rate-limit');
const multer = require('multer');

const app = express();
app.set('trust proxy', 1);

const uploadDir = path.join(__dirname, 'uploads');

if (!fs.existsSync(uploadDir)) {
    fs.mkdirSync(uploadDir);
}

const storage = multer.diskStorage({
    destination: (req, file, cb) => cb(null, uploadDir),
    filename: (req, file, cb) => {
        const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
        cb(null, uniqueSuffix + '.enc');
    }
});

const upload = multer({
    storage: storage,
    limits: { fileSize: 5 * 1024 * 1024 }
});

const allowedOrigins = process.env.CORS_ORIGIN
    ? process.env.CORS_ORIGIN.split(',')
    : ["https://gov.qa", "https://localhost:8080"];

app.use(cors({
    origin: function (origin, callback) {
        if (!origin) return callback(null, true);
        if (allowedOrigins.indexOf(origin) !== -1) {
            callback(null, true);
        } else {
            callback(new Error('Not allowed by CORS'));
        }
    },
    credentials: true
}));

const sslOptions = {
    key: fs.readFileSync('./certs/server.key'),
    cert: fs.readFileSync('./certs/server.cert')
};

const server = https.createServer(sslOptions, app);

const io = socketIo(server, {
    cors: {
        origin: allowedOrigins,
        methods: ["GET", "POST"],
        credentials: true
    }
});

const PORT = process.env.PORT || 8080;
const JWT_SECRET = process.env.JWT_SECRET;

if (!JWT_SECRET) {
    console.error("🚨 CRITICAL FATAL ERROR: JWT_SECRET is missing from environment variables!");
    process.exit(1);
}

app.use(express.json());

// Request Logger
app.use((req, res, next) => {
    console.log(`[HTTP] ${req.method} ${req.url}`);
    next();
});

const authLimiter = rateLimit({
    windowMs: 1 * 60 * 1000,
    max: 20,
    message: { error: "Too many login attempts, please try again after 15 minutes." },
    standardHeaders: true,
    legacyHeaders: false,
});

const apiLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    max: 100,
    message: { error: "Too many requests, please try again later." },
});

app.use('/api/', apiLimiter);

const isValidGovEmail = (email) => {
    return email.endsWith('@gov.qa');
};

const authenticateJWT = (req, res, next) => {
    const authHeader = req.headers.authorization;
    if (authHeader) {
        const token = authHeader.split(' ')[1];
        jwt.verify(token, JWT_SECRET, (err, user) => {
            if (err) return res.sendStatus(403);
            req.user = user;
            next();
        });
    } else {
        res.sendStatus(401);
    }
};

io.use((socket, next) => {
    if (socket.handshake.query && socket.handshake.query.token) {
        return next(new Error("SECURITY VIOLATION: Tokens in query parameters are forbidden."));
    }
    const token = socket.handshake.auth?.token;
    if (!token) return next(new Error("Authentication error: Token missing"));

    jwt.verify(token, JWT_SECRET, (err, decoded) => {
        if (err) return next(new Error("Authentication error: Invalid token"));
        socket.user = decoded;

        const isEnabled = process.env.GEO_FENCE_ENABLED === 'true';
        const allowedCountry = process.env.GEO_FENCE_COUNTRY || 'QA';

        if (isEnabled) {
            let ip = socket.handshake.address;
            if (socket.handshake.headers['x-forwarded-for']) {
                ip = socket.handshake.headers['x-forwarded-for'].split(',')[0].trim();
            }

            if (ip && ip.startsWith('::ffff:')) {
                ip = ip.substring(7);
            }

            if (ip && ip !== '::1' && ip !== '127.0.0.1' && !ip.startsWith('172.') && !ip.startsWith('192.168.') && !ip.startsWith('10.')) {
                const geo = geoip.lookup(ip);
                if (!geo || geo.country !== allowedCountry) {
                    return next(new Error(`GEO-BLOCK: Socket access restricted to ${allowedCountry}.`));
                }
            }
        }

        next();
    });
});

// --- Presence Tracking ---
const onlineUsers = new Map(); // userId -> Set(socketIds)

function isUserOnline(userId) {
    const sockets = onlineUsers.get(parseInt(userId));
    return sockets && sockets.size > 0;
}

async function getUserPrivacy(userId) {
    if (!userId) return { show_online: true, show_read_receipts: true };
    const id = parseInt(userId, 10);
    try {
        const res = await pool.query('SELECT show_online, show_read_receipts FROM users WHERE id = $1', [id]);
        return res.rows[0] || { show_online: true, show_read_receipts: true };
    } catch (e) {
        console.error(`[Privacy] Error for user ${id}:`, e.message);
        return { show_online: true, show_read_receipts: true };
    }
}

async function broadcastStatusChange(userId, status) {
    const privacy = await getUserPrivacy(userId);
    // If they want to hide their status, we only broadcast "offline" or nothing?
    // Standard behavior: if show_online is false, they always appear offline to others.
    const effectiveStatus = privacy.show_online ? status : 'offline';

    io.emit('userStatus', {
        userId: userId,
        status: effectiveStatus
    });
}

io.on('connection', async (socket) => {
    const userId = parseInt(socket.user?.id, 10);
    if (isNaN(userId)) return socket.disconnect();

    const userRoom = String(userId);
    socket.join(userRoom);

    // Track online state
    if (!onlineUsers.has(userId)) {
        onlineUsers.set(userId, new Set());
    }
    onlineUsers.get(userId).add(socket.id);

    // If it's the first socket for this user, broadcast Online
    if (onlineUsers.get(userId).size === 1) {
        console.log(`[Presence] User ${userId} (${socket.user?.username}) came ONLINE`);
        await broadcastStatusChange(userId, 'online');
    }

    // Send initial status of others to this user
    const currentStatuses = {};
    for (const [ouId, sockets] of onlineUsers.entries()) {
        if (sockets.size > 0 && ouId !== userId) {
            const privacy = await getUserPrivacy(ouId);
            if (privacy.show_online) {
                currentStatuses[String(ouId)] = 'online';
            }
        }
    }
    console.log(`[Presence] Sending initial statuses to ${userId}:`, currentStatuses);
    socket.emit('initialStatus', currentStatuses);

    socket.on('sendMessage', async (data) => {
        const receiverId = parseInt(data.receiverId, 10);
        const senderId = userId;

        try {
            const userRes = await pool.query('SELECT username FROM users WHERE id = $1', [senderId]);
            const senderUsername = userRes.rows[0]?.username || 'Unknown User';

            const isDelivered = isUserOnline(receiverId);

            const query = `
                INSERT INTO messages (sender_id, receiver_id, message_type, ciphertext, attachment_id, file_name, file_type, is_delivered)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
                RETURNING id, created_at;
            `;
            const values = [senderId, receiverId, data.messageType, data.ciphertext, data.attachment_id, data.file_name, data.file_type, isDelivered];
            const res = await pool.query(query, values);

            const msgData = {
                id: res.rows[0].id,
                senderId: senderId,
                senderUsername: senderUsername,
                messageType: data.messageType,
                ciphertext: data.ciphertext,
                timestamp: res.rows[0].created_at,
                isDelivered: isDelivered,
                isRead: false
            };

            io.to(String(receiverId)).emit('receiveMessage', msgData);

            // Also send back the ID to the sender for UI updates (ticks)
            socket.emit('messageAck', {
                tempId: data.tempId,
                id: res.rows[0].id,
                isDelivered: !!isDelivered
            });

        } catch (dbErr) {
            console.error(`[Socket] DB Error: ${dbErr.message}`);
        }
    });

    socket.on('markRead', async (data) => {
        const { senderId } = data; // the one who SENT the messages we are marking as read
        const myId = userId;

        try {
            const myPrivacy = await getUserPrivacy(myId);
            const senderPrivacy = await getUserPrivacy(senderId);

            await pool.query(
                'UPDATE messages SET is_read = TRUE WHERE sender_id = $1 AND receiver_id = $2 AND is_read = FALSE',
                [senderId, myId]
            );

            // Only notify sender if BOTH have read receipts enabled
            if (myPrivacy.show_read_receipts && senderPrivacy.show_read_receipts) {
                io.to(String(senderId)).emit('readReceipt', {
                    readBy: myId,
                    timestamp: new Date()
                });
            }
        } catch (e) {
            console.error("[Socket] markRead error:", e);
        }
    });

    socket.on('requestSessionReset', (data) => {
        const receiverId = data.receiverId;
        const senderId = userId;
        console.log(`🤝 [Socket] User ${senderId} requested a security reset from ${receiverId}`);
        io.to(String(receiverId)).emit('sessionReset', { senderId: senderId });
    });

    socket.on('disconnect', async () => {
        if (onlineUsers.has(userId)) {
            onlineUsers.get(userId).delete(socket.id);
            if (onlineUsers.get(userId).size === 0) {
                onlineUsers.delete(userId);
                await broadcastStatusChange(userId, 'offline');
            }
        }
    });
});

const geoFenceMiddleware = (req, res, next) => {
    const isEnabled = process.env.GEO_FENCE_ENABLED === 'true';
    const allowedCountry = process.env.GEO_FENCE_COUNTRY || 'QA';

    if (!isEnabled) {
        return next();
    }

    let ip = req.ip || req.connection.remoteAddress;

    if (ip && ip.startsWith('::ffff:')) {
        ip = ip.substring(7);
    }

    if (!ip || ip === '::1' || ip === '127.0.0.1' || ip.startsWith('172.') || ip.startsWith('192.168.') || ip.startsWith('10.')) {
        return next();
    }

    const geo = geoip.lookup(ip);

    if (geo && geo.country === allowedCountry) {
        next();
    } else {
        const userCountry = geo ? geo.country : 'Unknown Location';
        console.warn(`🚨 GEO-BLOCK: Denied access from ${userCountry} (IP: ${ip})`);
        res.status(403).json({ error: `Access restricted. Permitted region: ${allowedCountry}. Your region: ${userCountry}.` });
    }
};

app.use(geoFenceMiddleware);

app.get('/health', (req, res) => res.status(200).json({ status: 'UP' }));

app.post('/api/upload', authenticateJWT, upload.single('file'), (req, res) => {
    if (!req.file) return res.status(400).send('No file uploaded.');
    res.json({ attachment_id: req.file.filename });
});

app.get('/api/download/:attachment_id', authenticateJWT, (req, res) => {
    const fileId = req.params.attachment_id;
    if (!/^[a-zA-Z0-9.-]+$/.test(fileId)) return res.status(400).send('Invalid file ID');

    const filePath = path.join(uploadDir, fileId);
    if (!fs.existsSync(filePath)) return res.status(404).send('File not found.');

    res.download(filePath);
});

app.get('/api/auth/settings', authenticateJWT, async (req, res) => {
    console.log(`[HTTP] GET /api/auth/settings for user ${req.user.id}`);
    try {
        const result = await pool.query('SELECT show_online, show_read_receipts FROM users WHERE id = $1', [req.user.id]);
        if (result.rows.length === 0) return res.status(404).json({ error: "User not found" });
        res.json(result.rows[0]);
    } catch (e) {
        console.error("[HTTP] Get settings error:", e);
        res.status(500).json({ error: "Failed to fetch settings" });
    }
});

app.post('/api/auth/settings', authenticateJWT, async (req, res) => {
    const { show_online, show_read_receipts } = req.body;
    console.log(`[HTTP] POST /api/auth/settings for user ${req.user.id}:`, req.body);
    try {
        await pool.query(
            'UPDATE users SET show_online = $1, show_read_receipts = $2 WHERE id = $3',
            [show_online, show_read_receipts, req.user.id]
        );
        const status = isUserOnline(req.user.id) ? 'online' : 'offline';
        await broadcastStatusChange(req.user.id, status);
        res.json({ success: true });
    } catch (e) {
        console.error("[HTTP] Update settings error:", e);
        res.status(500).json({ error: "Failed to update settings" });
    }
});

app.post('/api/auth/register', authLimiter, async (req, res) => {
    try {
        const { username, email, password } = req.body;
        if (!isValidGovEmail(email)) return res.status(400).json({ error: "Restricted domain" });

        const salt = await bcrypt.genSalt(10);
        const password_hash = await bcrypt.hash(password, salt);
        const otp = generateOTP();
        const otp_hash = await bcrypt.hash(otp, salt);

        await pool.query(
            "INSERT INTO users (username, email, password_hash, mfa_secret, is_verified) VALUES ($1, $2, $3, $4, false) ON CONFLICT (email) DO UPDATE SET mfa_secret = $4",
            [username, email, password_hash, otp_hash]
        );
        console.log(`[DEBUG] OTP: ${otp}`);
        res.status(201).json({ message: "OTP sent." });
    } catch (err) { res.status(500).json({ error: "Registration failed" }); }
});

app.post('/api/auth/login', authLimiter, async (req, res) => {
    try {
        const { email, password } = req.body;
        const result = await pool.query("SELECT * FROM users WHERE email = $1", [email]);
        if (result.rows.length === 0) return res.status(401).json({ error: 'Invalid credentials' });

        const user = result.rows[0];
        if (!(await bcrypt.compare(password, user.password_hash))) return res.status(401).json({ error: 'Invalid credentials' });

        const otp = generateOTP();
        const otp_hash = await bcrypt.hash(otp, await bcrypt.genSalt(10));
        await pool.query("UPDATE users SET mfa_secret = $1 WHERE id = $2", [otp_hash, user.id]);

        console.log(`[DEBUG] OTP: ${otp}`);
        const tempToken = jwt.sign({ id: user.id, email: user.email, username: user.username, type: 'pre-auth' }, JWT_SECRET, { expiresIn: '5m' });
        res.json({ token: tempToken, message: "OTP sent." });
    } catch (err) { res.status(500).json({ error: "Login failed" }); }
});

app.post('/api/auth/verify-otp', authLimiter, async (req, res) => {
    const { email, otp } = req.body;
    try {
        const userResult = await pool.query("SELECT id, mfa_secret, username FROM users WHERE email = $1", [email]);
        if (userResult.rows.length === 0) return res.status(404).json({ error: "User not found" });
        const user = userResult.rows[0];

        if (await bcrypt.compare(otp, user.mfa_secret)) {
            await pool.query("UPDATE users SET is_verified = true, mfa_secret = NULL WHERE id = $1", [user.id]);
            const token = jwt.sign({ id: user.id, email: email, username: user.username }, JWT_SECRET, { expiresIn: '24h' });
            res.json({ token, user: { id: user.id, username: user.username, email } });
        } else {
            res.status(401).json({ error: "Invalid OTP" });
        }
    } catch (e) { res.status(500).json({ error: "Verification Error" }); }
});

app.get('/api/auth/search', authenticateJWT, async (req, res) => {
    try {
        const result = await pool.query("SELECT id, username, email FROM users WHERE LOWER(email) = LOWER($1) AND is_verified = true", [req.query.email]);
        if (result.rows.length === 0) return res.status(404).json({ error: "User not found" });
        res.json(result.rows[0]);
    } catch (err) { res.status(500).json({ error: "Error searching user" }); }
});

app.get('/api/chat/history/:partnerId', authenticateJWT, async (req, res) => {
    try {
        const myId = req.user.id;
        const partnerId = parseInt(req.params.partnerId, 10);

        const myPrivacy = await getUserPrivacy(myId);
        const partnerPrivacy = await getUserPrivacy(partnerId);

        // Standard privacy logic: If either user has receipts OFF, nobody sees blue ticks
        const showReceipts = myPrivacy.show_read_receipts && partnerPrivacy.show_read_receipts;

        const result = await pool.query(
            "SELECT * FROM messages WHERE (sender_id = $1 AND receiver_id = $2) OR (sender_id = $2 AND receiver_id = $1) ORDER BY created_at ASC",
            [myId, partnerId]
        );

        res.json(result.rows.map(row => ({
            id: row.id.toString(),
            senderId: row.sender_id.toString(),
            receiverId: row.receiver_id.toString(),
            messageType: row.message_type,
            ciphertext: row.ciphertext,
            attachment_id: row.attachment_id,
            file_name: row.file_name,
            file_type: row.file_type,
            timestamp: row.created_at,
            isDelivered: row.is_delivered,
            isRead: showReceipts ? row.is_read : false
        })));
    } catch (err) {
        console.error("[HTTP] History error:", err);
        res.status(500).json({ error: "Failed to fetch history" });
    }
});

app.post('/api/auth/keys', authenticateJWT, keyController.publishKeys);
app.get('/api/auth/keys/count', authenticateJWT, keyController.getPreKeyCount);
app.get('/api/auth/keys/:userId', authenticateJWT, keyController.getPublicKeyBundle);

app.use((err, req, res, next) => {
    if (err instanceof multer.MulterError) {
        if (err.code === 'LIMIT_FILE_SIZE') return res.status(413).json({ error: "File too large. Max 5MB." });
    }
    console.error('[Error]', err.stack);
    res.status(500).json({ error: 'Internal server error' });
});

server.listen(PORT, () => {
    console.log(`[GovComm] Server running on port ${PORT}`);
});