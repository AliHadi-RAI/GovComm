const axios = require('axios');
const { Client } = require('pg');

const API_URL = 'http://localhost:8080/api/auth';
const DB_CONFIG = {
  user: 'govcomm_user',
  host: 'localhost',
  database: 'govcomm_db',
  password: 'secure_password',
  port: 5432,
};

const TEST_EMAIL = 'alice@gov.qa';
const TEST_PASSWORD = '123456';

async function runMFATest() {
  const client = new Client(DB_CONFIG);
  try {
    await client.connect();
    console.log('🚀 Connected to govcomm_db. Starting 25-cycle MFA test...\n');
    console.log('------------------------------------------------------------');
    console.log('Attempt | OTP Code | Login Latency | Verify Latency | Status');
    console.log('------------------------------------------------------------');

    let totalLatency = 0;
    let successCount = 0;

    for (let i = 1; i <= 25; i++) {
      const startLogin = Date.now();
      await axios.post(`${`${API_URL}/login`}`, { email: TEST_EMAIL, password: TEST_PASSWORD });
      const loginLatency = Date.now() - startLogin;

      const res = await client.query('SELECT mfa_secret FROM users WHERE email = $1', [TEST_EMAIL]);
      const otp = res.rows[0].mfa_secret;

      const startVerify = Date.now();
      const verifyRes = await axios.post(`${`${API_URL}/verify-otp`}`, { email: TEST_EMAIL, otp: otp });
      const verifyLatency = Date.now() - startVerify;

      totalLatency += (loginLatency + verifyLatency);

      if (verifyRes.status === 200 || verifyRes.status === 201) {
        successCount++;
        console.log(`${i.toString().padEnd(8)}| ${otp.padEnd(9)}| ${loginLatency.toString().padEnd(14)}ms | ${verifyLatency.toString().padEnd(15)}ms | ✅ OK`);
      } else {
        console.log(`${i.toString().padEnd(8)}| ${otp.padEnd(9)}| ${loginLatency.toString().padEnd(14)}ms | ${verifyLatency.toString().padEnd(15)}ms | ❌ FAIL`);
      }
    }

    const avgLatency = (totalLatency / 25).toFixed(2);
    console.log('------------------------------------------------------------');
    console.log(`\n📊 FINAL REPORT DATA:`);
    console.log(`- Success Rate: ${(successCount / 25) * 100}%`);
    console.log(`- Average Full-Auth Latency: ${avgLatency}ms`);
    console.log('------------------------------------------------------------');

  } catch (err) {
    console.error('\n❌ ERROR:', err.response ? `Status ${err.response.status}: ${JSON.stringify(err.response.data)}` : err.message);
  } finally {
    await client.end();
  }
}

runMFATest();