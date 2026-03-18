const pool = require('../db');

exports.getPreKeyCount = async (req, res) => {
    try {
        const userId = req.user.id;
        const result = await pool.query(
            "SELECT COUNT(*) FROM pre_keys WHERE user_id = $1 AND is_used = FALSE", 
            [userId]
        );
        
        const count = parseInt(result.rows[0].count);
        console.log(`[Keys] User ${userId} has ${count} unused OPKs remaining.`);
        
        res.status(200).json({ count: count });
    } catch (err) {
        console.error("Error fetching pre-key count:", err);
        res.status(500).json({ error: "Failed to fetch pre-key count" });
    }
};

exports.publishKeys = async (req, res) => {
    const { identityKey, signedPreKey, preKeys } = req.body;
    const userId = req.user.id;
    const { PublicKey } = await import('@signalapp/libsignal-client');

    if (identityKey && signedPreKey) {
        try {
            const idKeyBuffer = Buffer.from(identityKey, 'base64');
            const spkBuffer = Buffer.from(signedPreKey.publicKey, 'base64');
            const signatureBuffer = Buffer.from(signedPreKey.signature, 'base64');

            const officialIdentityKey = PublicKey.deserialize(idKeyBuffer);

            const isValid = officialIdentityKey.verify(spkBuffer, signatureBuffer);

            if (!isValid) {
                console.warn(`[Security] Invalid SPK signature rejected for User ${userId}`);
                return res.status(400).json({ error: "INTEGRITY HOLE: Invalid Signed Pre-Key signature." });
            }
        } catch (error) {
            console.error("[Security] Malformed cryptographic keys submitted:", error.message);
            return res.status(400).json({ error: "Malformed cryptographic keys." });
        }
    }

    const client = await pool.connect();

    try {
        await client.query('BEGIN');
        
        if (identityKey) {
            await client.query(
                'INSERT INTO identity_keys (user_id, public_key) VALUES ($1, $2) ON CONFLICT (user_id) DO UPDATE SET public_key = $2',
                [userId, identityKey]
            );
        }

        if (signedPreKey) {
            const spkId = signedPreKey.keyId || signedPreKey.id;
            if (spkId === undefined || spkId === null) {
                throw new Error("Signed Pre-Key ID is required.");
            }
            await client.query(
                'INSERT INTO signed_pre_keys (user_id, key_id, public_key, signature) VALUES ($1, $2, $3, $4) ON CONFLICT (user_id) DO UPDATE SET public_key = $3, signature = $4, key_id = $2',
                [userId, spkId, signedPreKey.publicKey, signedPreKey.signature]
            );
        }


        if (preKeys && preKeys.length > 0) {
            // 🛠️ FIX: Do NOT delete existing keys blindly. 
            // Instead, insert only new, unique keys to prevent an attacker from replaying an old upload payload.
            
            for (let key of preKeys) {
                const pkId = key.keyId || key.id;
                if (pkId !== undefined && pkId !== null) {
                    // Requires a UNIQUE constraint on (user_id, key_id) in the database
                    await client.query(
                        `INSERT INTO pre_keys (user_id, key_id, public_key, is_used) 
                        VALUES ($1, $2, $3, FALSE) 
                        ON CONFLICT (user_id, key_id) DO NOTHING`, 
                        [userId, pkId, key.publicKey]
                    );
                }
            }
        }

        await client.query('COMMIT');
        res.status(200).json({ message: "X3DH Bundle published successfully" });
        
    } catch (err) {
        await client.query('ROLLBACK');
        console.error("Publish Keys Error:", err.message);
        res.status(500).json({ error: "Failed to publish keys", details: err.message });
    } finally {
        client.release();
    }
};

exports.getPublicKeyBundle = async (req, res) => {
    const targetUserId = parseInt(req.params.userId, 10);
    if (isNaN(targetUserId)) {
        return res.status(400).json({ error: "Invalid user ID format. Expected integer." });
    }
    const client = await pool.connect();

    try {
        await client.query('BEGIN');
        const identityData = await client.query(
            'SELECT public_key FROM identity_keys WHERE user_id = $1',
            [targetUserId]
        );

        const signedPreKeyData = await client.query(
            'SELECT key_id, public_key, signature FROM signed_pre_keys WHERE user_id = $1',
            [targetUserId]
        );

        const preKeyData = await client.query(
            'SELECT id, key_id, public_key FROM pre_keys WHERE user_id = $1 AND is_used = FALSE LIMIT 1 FOR UPDATE SKIP LOCKED',
            [targetUserId]
        );

        if (identityData.rows.length === 0 || signedPreKeyData.rows.length === 0) {
            await client.query('ROLLBACK');
            return res.status(404).json({ error: "User encryption bundle not found or incomplete." });
        }

        const bundle = {
            identityKey: identityData.rows[0].public_key,
            signedPreKey: {
                keyId: signedPreKeyData.rows[0].key_id,
                publicKey: signedPreKeyData.rows[0].public_key,
                signature: signedPreKeyData.rows[0].signature
            },
            preKey: null
        };

        if (preKeyData.rows.length > 0) {
            bundle.preKey = {
                keyId: preKeyData.rows[0].key_id,
                publicKey: preKeyData.rows[0].public_key 
            };
            
            await client.query(
                'UPDATE pre_keys SET is_used = TRUE WHERE id = $1',
                [preKeyData.rows[0].id]
            );
        }

        await client.query('COMMIT');
        res.status(200).json(bundle);

    } catch (err) {
        await client.query('ROLLBACK');
        console.error("Fetch Bundle Error:", err.message);
        res.status(500).json({ error: "Failed to retrieve public key bundle" });
    } finally {
        client.release();
    }
};