const axios = require('axios');
const io = require('socket.io-client');

const API_URL = 'http://localhost:8080/api';
const SOCKET_URL = 'http://localhost:8080';

const runId = Math.floor(Math.random() * 10000);

const user1 = { username: `layla_${runId}`, email: `layla_${runId}@gov.qa`, password: 'password123' };
const user2 = { username: `khalid_${runId}`, email: `khalid_${runId}@gov.ae`, password: 'password123' };

const mockKeys = {
    identityKey: "base64_identity_key",
    signedPreKey: { keyId: 1, publicKey: "base64", signature: "base64" },
    preKeys: [{ keyId: 0, publicKey: "base64" }]
};

let token1, token2, id1, id2, socket2;

async function runTest() {
    console.log(`🚀 Starting Test Run #${runId}...\n`);

    try {
        console.log(`1️⃣  Registering & Logging In...`);
        await axios.post(`${API_URL}/auth/register`, user1);
        await axios.post(`${API_URL}/auth/register`, user2);
        
        const res1 = await axios.post(`${API_URL}/auth/login`, { email: user1.email, password: user1.password });
        token1 = res1.data.token;
        id1 = res1.data.user.id;
        
        const res2 = await axios.post(`${API_URL}/auth/login`, { email: user2.email, password: user2.password });
        token2 = res2.data.token;
        id2 = res2.data.user.id;
        console.log(`   ✅ Logged In: ${user1.username} (ID: ${id1}) & ${user2.username} (ID: ${id2})`);

        console.log("\n2️⃣  Connecting Receiver...");
        socket2 = io(SOCKET_URL, {
            auth: { token: token2 },    
            query: { token: token2 },  
            transports: ['websocket'],
            forceNew: true
        });

        await new Promise((resolve) => {
            socket2.on('connect', () => {
                console.log(`   ✅ Receiver Connected!`);
                resolve();
            });
        });

        console.log(`\n3️⃣  Connecting Sender...`);
        const socket1 = io(SOCKET_URL, {
            auth: { token: token1 },
            query: { token: token1 },
            transports: ['websocket'],
            forceNew: true
        });

        socket1.on('connect', async () => {
            console.log(`   ✅ Sender Connected! Waiting 1s...`);
            
            await new Promise(r => setTimeout(r, 1000));

            const payload = {
                receiverId: String(id2),
                ciphertext: "SECRET_CIPHERTEXT",
                iv: "IV_123",
                ratchetPublicKey: "KEY_XYZ",
                counter: 1
            };

            console.log(`   📤 Emitting 'sendMessage' to ID: ${payload.receiverId}`);
            socket1.emit('sendMessage', payload);
        });

        await new Promise((resolve, reject) => {
            socket2.on('receiveMessage', (data) => {
                console.log(`\n🎉 SUCCESS: Message Received by Receiver!`);
                console.log("   📂 Data:", data);
                resolve();
            });
            setTimeout(() => reject(new Error("Message Receive Timeout (5s)")), 5000);
        });

        console.log("\n✅✅✅ TEST PASSED ✅✅✅");
        process.exit(0);

    } catch (error) {
        console.error("\n❌ TEST FAILED:", error.message);
        process.exit(1);
    }
}

runTest();