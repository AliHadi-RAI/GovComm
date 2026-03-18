function formatKeyBundleForBackend(userId, identityKey, preKeys) {
  return {
    userId: userId,
    identityKey: identityKey,
    preKeys: preKeys.map(k => ({
      key_id: k.key_id,
      content: k.public_key
    }))
  };
}

module.exports = { formatKeyBundleForBackend };