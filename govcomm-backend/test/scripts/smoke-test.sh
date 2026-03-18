

echo "Testing PostgreSQL..."
docker exec govccomm-db pg_isready -U govcomm_user && echo "✅ DB OK" || echo "❌ DB FAIL"

echo "Testing Backend..."
curl -s http://localhost:8080/health > /dev/null && echo "✅ Backend OK" || echo "❌ Backend FAIL"