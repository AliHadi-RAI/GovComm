
function simulateClientEncrypt(message) {
  return 'ciphertext_' + Buffer.from(message).toString('base64');
}

function simulateServerRelay(ciphertext) {
  try {
    const decoded = Buffer.from(ciphertext.replace('ciphertext_', ''), 'base64').toString();
    console.log('❌ Server read message:', decoded);
    return false;
  } catch (e) {
    console.log('✅ Zero-knowledge verified: Server cannot read');
    return true;
  }
}
const plaintext = 'Classified message';
const ciphertext = simulateClientEncrypt(plaintext);
simulateServerRelay(ciphertext);