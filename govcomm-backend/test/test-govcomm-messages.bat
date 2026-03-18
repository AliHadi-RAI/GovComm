@echo off
setlocal enabledelayedexpansion

:: ============================================
:: GovComm Backend Message Test Script
:: Tests: Login, OTP, Socket Connection, Message Sending
:: ============================================

echo ============================================
echo    GovComm Backend Test Suite
echo ============================================
echo.

:: Configuration
set BASE_URL=http://localhost:8080
set ALICE_EMAIL=alice@gov.qa
set BOB_EMAIL=bob@gov.qa
set PASSWORD=123456

:: Temporary files for tokens
set ALICE_TOKEN_FILE=%TEMP%\alice_token.txt
set BOB_TOKEN_FILE=%TEMP%\bob_token.txt
set ALICE_OTP_FILE=%TEMP%\alice_otp.txt
set BOB_OTP_FILE=%TEMP%\bob_otp.txt

echo [1/10] Checking server health...
curl -s %BASE_URL%/health | findstr "UP" >nul
if errorlevel 1 (
    echo [FAIL] Server is not running!
    echo Please start the server first: node server.js
    pause
    exit /b 1
)
echo [PASS] Server is UP
echo.

:: ============================================
:: ALICE REGISTRATION/LOGIN
:: ============================================

echo [2/10] Alice: Registering...
curl -s -X POST %BASE_URL%/api/auth/register ^
  -H "Content-Type: application/json" ^
  -d "{\"username\":\"alice\",\"email\":\"%ALICE_EMAIL%\",\"password\":\"%PASSWORD%\"}" > %TEMP%\alice_reg.json

findstr "OTP sent" %TEMP%\alice_reg.json >nul
if errorlevel 1 (
    echo [INFO] Alice may already exist, continuing to login...
) else (
    echo [PASS] Alice registered successfully
)
echo.

echo [3/10] Alice: Logging in...
curl -s -X POST %BASE_URL%/api/auth/login ^
  -H "Content-Type: application/json" ^
  -d "{\"email\":\"%ALICE_EMAIL%\",\"password\":\"%PASSWORD%\"}" > %TEMP%\alice_login.json

findstr "token" %TEMP%\alice_login.json >nul
if errorlevel 1 (
    echo [FAIL] Alice login failed!
    type %TEMP%\alice_login.json
    pause
    exit /b 1
)

:: Extract temp token (simplified - assumes token is first in response)
for /f "tokens=2 delims=:{}" %%a in (%TEMP%\alice_login.json) do (
    set ALICE_TEMP_TOKEN=%%a
    set ALICE_TEMP_TOKEN=!ALICE_TEMP_TOKEN:"=!
    set ALICE_TEMP_TOKEN=!ALICE_TEMP_TOKEN: =!
    goto :got_alice_temp
)
:got_alice_temp
echo [PASS] Alice temp token received
echo.

echo [4/10] Alice: Getting OTP from server logs...
echo Please check the server console and enter Alice's OTP:
set /p ALICE_OTP="Enter Alice OTP: "

echo [5/10] Alice: Verifying OTP...
curl -s -X POST %BASE_URL%/api/auth/verify-otp ^
  -H "Content-Type: application/json" ^
  -d "{\"email\":\"%ALICE_EMAIL%\",\"otp\":\"%ALICE_OTP%\"}" > %TEMP%\alice_verify.json

findstr "token" %TEMP%\alice_verify.json >nul
if errorlevel 1 (
    echo [FAIL] Alice OTP verification failed!
    type %TEMP%\alice_verify.json
    pause
    exit /b 1
)

:: Extract final token
for /f "tokens=2 delims=:{}" %%a in ('findstr "token" %TEMP%\alice_verify.json') do (
    set ALICE_TOKEN=%%a
    set ALICE_TOKEN=!ALICE_TOKEN:"=!
    set ALICE_TOKEN=!ALICE_TOKEN: =!
    goto :got_alice_token
)
:got_alice_token
echo !ALICE_TOKEN! > %ALICE_TOKEN_FILE%
echo [PASS] Alice authenticated successfully
echo Token saved to: %ALICE_TOKEN_FILE%
echo.

:: ============================================
:: BOB REGISTRATION/LOGIN
:: ============================================

echo [6/10] Bob: Registering...
curl -s -X POST %BASE_URL%/api/auth/register ^
  -H "Content-Type: application/json" ^
  -d "{\"username\":\"bob\",\"email\":\"%BOB_EMAIL%\",\"password\":\"%PASSWORD%\"}" > %TEMP%\bob_reg.json

findstr "OTP sent" %TEMP%\bob_reg.json >nul
if errorlevel 1 (
    echo [INFO] Bob may already exist, continuing to login...
) else (
    echo [PASS] Bob registered successfully
)
echo.

echo [7/10] Bob: Logging in...
curl -s -X POST %BASE_URL%/api/auth/login ^
  -H "Content-Type: application/json" ^
  -d "{\"email\":\"%BOB_EMAIL%\",\"password\":\"%PASSWORD%\"}" > %TEMP%\bob_login.json

findstr "token" %TEMP%\bob_login.json >nul
if errorlevel 1 (
    echo [FAIL] Bob login failed!
    type %TEMP%\bob_login.json
    pause
    exit /b 1
)

:: Extract temp token
for /f "tokens=2 delims=:{}" %%a in (%TEMP%\bob_login.json) do (
    set BOB_TEMP_TOKEN=%%a
    set BOB_TEMP_TOKEN=!BOB_TEMP_TOKEN:"=!
    set BOB_TEMP_TOKEN=!BOB_TEMP_TOKEN: =!
    goto :got_bob_temp
)
:got_bob_temp
echo [PASS] Bob temp token received
echo.

echo [8/10] Bob: Getting OTP from server logs...
echo Please check the server console and enter Bob's OTP:
set /p BOB_OTP="Enter Bob OTP: "

echo [9/10] Bob: Verifying OTP...
curl -s -X POST %BASE_URL%/api/auth/verify-otp ^
  -H "Content-Type: application/json" ^
  -d "{\"email\":\"%BOB_EMAIL%\",\"otp\":\"%BOB_OTP%\"}" > %TEMP%\bob_verify.json

findstr "token" %TEMP%\bob_verify.json >nul
if errorlevel 1 (
    echo [FAIL] Bob OTP verification failed!
    type %TEMP%\bob_verify.json
    pause
    exit /b 1
)

:: Extract final token
for /f "tokens=2 delims=:{}" %%a in ('findstr "token" %TEMP%\bob_verify.json') do (
    set BOB_TOKEN=%%a
    set BOB_TOKEN=!BOB_TOKEN:"=!
    set BOB_TOKEN=!BOB_TOKEN: =!
    goto :got_bob_token
)
:got_bob_token
echo !BOB_TOKEN! > %BOB_TOKEN_FILE%
echo [PASS] Bob authenticated successfully
echo Token saved to: %BOB_TOKEN_FILE%
echo.

:: ============================================
:: SOCKET TEST SETUP
:: ============================================

echo [10/10] Preparing WebSocket test...
echo.
echo ============================================
echo    MANUAL TEST REQUIRED
echo ============================================
echo.
echo Step A: Open TWO new CMD windows
echo.
echo Step B: In FIRST window (Alice), run:
echo   wscat -c "ws://localhost:8080/socket.io/?EIO=4^&transport=websocket^&token=!ALICE_TOKEN!"
echo.
echo Step C: In SECOND window (Bob), run:
echo   wscat -c "ws://localhost:8080/socket.io/?EIO=4^&transport=websocket^&token=!BOB_TOKEN!"
echo.
echo Step D: Send test messages:
echo.
echo   Alice sends to Bob (in Alice's window):
echo   42["sendMessage",{"receiverId":"2","ciphertext":"SGVsbG8gQm9i","iv":"dGVzdGl2","mac":"dGVzdG1hYw==","ratchetPublicKey":"dGVzdGtleQ==","counter":1}]
echo.
echo   Bob sends to Alice (in Bob's window):
echo   42["sendMessage",{"receiverId":"1","ciphertext":"SGVsbG8gQWxpY2U=","iv":"dGVzdGl2","mac":"dGVzdG1hYw==","ratchetPublicKey":"dGVzdGtleQ==","counter":1}]
echo.
echo Step E: Verify receipt in opposite windows
echo.
echo ============================================
echo    AUTOMATED MESSAGE TEST
echo ============================================
echo.

choice /C YN /M "Do you want to run automated HTTP message test (no real-time)?"

if errorlevel 2 goto :skip_http_test

echo.
echo Running HTTP API tests...
echo.

:: Test Alice's keys
echo Testing Alice's key endpoint...
curl -s -H "Authorization: Bearer !ALICE_TOKEN!" %BASE_URL%/api/auth/keys/1 | findstr "identityKey" >nul
if errorlevel 1 (
    echo [WARN] Alice's keys not found, publishing test keys...
    curl -s -X POST %BASE_URL%/api/auth/keys ^
      -H "Authorization: Bearer !ALICE_TOKEN!" ^
      -H "Content-Type: application/json" ^
      -d "{\"identityKey\":\"YWxpY2VfaWQ=\",\"signedPreKey\":{\"keyId\":1,\"publicKey\":\"YWxpY2Vfc3Br\",\"signature\":\"c2ln\"},\"preKeys\":[{\"keyId\":1,\"publicKey\":\"YWxpY2Vfb3Br\"}]}"
)

:: Test Bob's keys
echo Testing Bob's key endpoint...
curl -s -H "Authorization: Bearer !BOB_TOKEN!" %BASE_URL%/api/auth/keys/2 | findstr "identityKey" >nul
if errorlevel 1 (
    echo [WARN] Bob's keys not found, publishing test keys...
    curl -s -X POST %BASE_URL%/api/auth/keys ^
      -H "Authorization: Bearer !BOB_TOKEN!" ^
      -H "Content-Type: application/json" ^
      -d "{\"identityKey\":\"Ym9iX2lk\",\"signedPreKey\":{\"keyId\":1,\"publicKey\":\"Ym9iX3Nwaw==\",\"signature\":\"c2ln\"},\"preKeys\":[{\"keyId\":1,\"publicKey\":\"Ym9iX29waw==\"}]}"
)

:: Test search
echo Testing user search...
curl -s -H "Authorization: Bearer !ALICE_TOKEN!" "%BASE_URL%/api/auth/search?email=bob@gov.qa" | findstr "id" >nul
if errorlevel 1 (
    echo [FAIL] Search failed
) else (
    echo [PASS] Search working
)

:: Test chat history
echo Testing chat history...
curl -s -H "Authorization: Bearer !ALICE_TOKEN!" %BASE_URL%/api/chat/history/2 > %TEMP%\history.json
echo [INFO] Chat history response:
type %TEMP%\history.json
echo.

:skip_http_test

echo.
echo ============================================
echo    TEST SUMMARY
echo ============================================
echo Alice Token: !ALICE_TOKEN:~0,20!...
echo Bob Token: !BOB_TOKEN:~0,20!...
echo.
echo Token files:
echo   Alice: %ALICE_TOKEN_FILE%
echo   Bob: %BOB_TOKEN_FILE%
echo.
echo To test WebSocket manually, use the commands above.
echo.
pause