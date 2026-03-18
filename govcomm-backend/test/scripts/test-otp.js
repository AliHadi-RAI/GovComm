
function generateOTP() {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

function verifyOTP(otp, storedOTP) {
  return otp === storedOTP;
}

console.log('=== OTP Test ===');
const testOTP = generateOTP();
console.log('Generated OTP:', testOTP);
console.log('Verification (correct):', verifyOTP(testOTP, testOTP) ? 'PASS' : ' FAIL');
console.log('Verification (wrong):', verifyOTP('000000', testOTP) ? ' FAIL' : 'PASS');

module.exports = { generateOTP, verifyOTP };