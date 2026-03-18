require('dotenv').config();

const pool = require('../db');
const { publishKeys } = require('../controllers/keyController');

const mockRes = () => {
    const res = {};
    res.status = (code) => {
        res.statusCode = code;
        return res;
    };
    res.json = (data) => {
        res.body = data;
        return res;
    };
    return res;
};

async function runReplayAttackTest() {
    console.log("============================================");
    console.log("🛡️ STARTING REPLAY ATTACK VULNERABILITY TEST");
    console.log("============================================\n");

    const testUserId = 999;

    try {
        await pool.query(`
            INSERT INTO users (id, username, email, password_hash) 
            VALUES ($1, 'testuser_999', 'test999@govcomm.test', 'dummyhash') 
            ON CONFLICT (id) DO NOTHING
        `, [testUserId]);

        await pool.query('DELETE FROM pre_keys WHERE user_id = $1', [testUserId]);

        console.log("📤 Step 1: User uploads initial Pre-Keys [IDs 1, 2, 3]...");
        const payload1 = {
            preKeys: [
                { keyId: 1, publicKey: "PubKey1_Base64" },
                { keyId: 2, publicKey: "PubKey2_Base64" },
                { keyId: 3, publicKey: "PubKey3_Base64" }
            ]
        };
        
        const req1 = { user: { id: testUserId }, body: payload1 };
        let res1 = mockRes();
        await publishKeys(req1, res1);

        console.log("📤 Step 2: User runs low, uploads new Pre-Keys [IDs 4, 5, 6]...");
        const payload2 = {
            preKeys: [
                { keyId: 4, publicKey: "PubKey4_Base64" },
                { keyId: 5, publicKey: "PubKey5_Base64" },
                { keyId: 6, publicKey: "PubKey6_Base64" }
            ]
        };
        
        const req2 = { user: { id: testUserId }, body: payload2 };
        let res2 = mockRes();
        await publishKeys(req2, res2);

        console.log("😈 Step 3: Attacker intercepts and replays the old payload from Step 1!");
        const req3 = { user: { id: testUserId }, body: payload1 };
        let res3 = mockRes();
        await publishKeys(req3, res3);

        console.log("🔍 Step 4: Verifying database state...");
        const result = await pool.query('SELECT key_id FROM pre_keys WHERE user_id = $1 ORDER BY key_id ASC', [testUserId]);
        const finalKeys = result.rows.map(row => row.key_id);
        
        console.log(`📊 Keys currently in DB: [${finalKeys.join(', ')}]`);

        const hasKey4 = finalKeys.includes(4);
        const hasKey5 = finalKeys.includes(5);
        const hasKey6 = finalKeys.includes(6);

        if (hasKey4 && hasKey5 && hasKey6) {
            console.log("\n✅ TEST PASSED: Replay attack neutralized! Fresh keys were NOT deleted.");
        } else {
            console.error("\n❌ TEST FAILED: VULNERABILITY DETECTED! The attacker successfully wiped out the fresh keys via a replay attack.");
        }

    } catch (error) {
        console.error("Test Error:", error);
    } finally {
        await pool.query('DELETE FROM pre_keys WHERE user_id = $1', [testUserId]);
        await pool.query('DELETE FROM users WHERE id = $1', [testUserId]);
        pool.end();
    }
}

runReplayAttackTest();