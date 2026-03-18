const axios = require('axios');
const https = require('https');

// Ignore self-signed certificate errors for local testing
const agent = new https.Agent({  
  rejectUnauthorized: false
});

async function runBruteForceTest() {
    console.log("============================================");
    console.log("🛡️ STARTING BRUTE FORCE VULNERABILITY TEST");
    console.log("============================================\n");

    let successCount = 0;
    let blockCount = 0;

    // Simulate an attacker trying 8 passwords rapidly
    for (let i = 1; i <= 8; i++) {
        try {
            console.log(`🥷 Attacker attempt ${i}...`);
            
            // We use validateStatus to prevent axios from throwing on 4xx errors
            const res = await axios.post('https://localhost:8080/api/auth/login', {
                email: 'admin@gov.qa',
                password: `wrongpassword${i}`
            }, { 
                httpsAgent: agent,
                validateStatus: () => true 
            });

            if (res.status === 401) {
                console.log(`   -> [401] Server checked DB and rejected bad password. (Normal)`);
                successCount++;
            } else if (res.status === 429) {
                console.log(`   -> [429] 🛑 BLOCKED BY RATE LIMITER: ${res.data.error}`);
                blockCount++;
            } else {
                console.log(`   -> [${res.status}] Unexpected response.`);
            }

        } catch (err) {
            console.error("Test Error:", err.message);
        }
    }

    console.log("\n============================================");
    if (blockCount > 0) {
        console.log(`✅ TEST PASSED: The attacker was successfully blocked after 5 attempts.`);
    } else {
        console.error(`❌ TEST FAILED: VULNERABILITY DETECTED! The attacker made ${successCount} attempts without being blocked.`);
    }
}

runBruteForceTest();