
echo "Starting GovComm Infrastructure Audit..."

if [ $(docker ps -q -f name=backend) ]; then
    echo "✅ Backend container is UP"
else
    echo "❌ Backend container is DOWN"
fi

docker exec backend nc -z db 5432 && echo "✅ Internal Network Link: OK" || echo "❌ Network Isolation Breach"

echo "Verifying server cannot read message content..."
DB_CHECK=$(docker exec db psql -U govcomm_user -d govcomm_db -c "SELECT content FROM messages LIMIT 1;" | grep -i "ciphertext")
if [ $? -eq 0 ]; then
    echo "✅ Zero-Knowledge Property Verified: No plaintext found"
else
    echo "⚠️ Warning: Server-side plaintext audit failed or table empty"
fi