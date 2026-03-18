$iterations = 20

Write-Host "Starting Docker Compose benchmark..."

for ($i = 1; $i -le $iterations; $i++) {
    Write-Host "=============================="
    Write-Host "Iteration $i"


    $startUp = Get-Date
    docker compose up -d | Out-Null
    $endUp = Get-Date
    $upTime = ($endUp - $startUp).TotalSeconds
    Write-Host "UP latency: $upTime seconds"


    $startDown = Get-Date
    docker compose down | Out-Null
    $endDown = Get-Date
    $downTime = ($endDown - $startDown).TotalSeconds
    Write-Host "DOWN latency: $downTime seconds"
}

Write-Host "=============================="
Write-Host "Benchmark completed. Press Enter to exit."
Read-Host
