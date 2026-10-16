# Lab 12 — Docker-side perf measurement (run on the author's laptop).
# Measures the Lab 6 container (quicknotes:lab6) exactly like the Spin side
# is measured in scripts/lab12-warm-spin.py / lab12-coldstart-spin.py:
#   warm latency: keep-alive HTTP loop, 5 warmup + 50 measured, nearest-rank p50/p95
#   cold start:   container removed + re-created, time to first HTTP 200, 5 samples
#   artifact:     docker image inspect --format '{{.Size}}' (bytes, on disk)
#
# Usage (PowerShell, from the repo root):
#   powershell -ExecutionPolicy Bypass -File scripts\lab12-docker-perf.ps1

$ErrorActionPreference = "Stop"
$image = "quicknotes:lab6"
$port  = 18080
$name  = "lab6-perf"

# --- 0. image present? (rebuild from app/Dockerfile if the tag is gone)
$imgs = docker image ls --format "{{.Repository}}:{{.Tag}}" | Select-String -SimpleMatch $image
if (-not $imgs) {
    Write-Output "image $image not found - building from ./app"
    docker build -t $image ./app
}

# --- 1. artifact size (bytes on disk)
$size = docker image inspect $image --format "{{.Size}}"
Write-Output "docker_image_size_bytes=$size"

# --- 2. warm latency (keep-alive, 5 warmup + 50 measured)
Add-Type -AssemblyName System.Net.Http
$client = New-Object System.Net.Http.HttpClient
$client.Timeout = [TimeSpan]::FromSeconds(5)
$base = "http://127.0.0.1:${port}/health"

docker rm -f $name 2>$null | Out-Null
docker run -d --name $name -p "${port}:8080" $image | Out-Null
Start-Sleep -Milliseconds 1500

1..5 | ForEach-Object { $client.GetAsync($base).Result | Out-Null }
$times = 1..50 | ForEach-Object {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $resp = $client.GetAsync($base).Result
    $sw.Stop()
    if (-not $resp.IsSuccessStatusCode) { throw "GET /health not 200" }
    $sw.Elapsed.TotalMilliseconds
}
$client.Dispose()
$srt = $times | Sort-Object
Write-Output ("warm_p50_ms={0:N3}" -f $srt[24])   # nearest-rank, 25th of 50
Write-Output ("warm_p95_ms={0:N3}" -f $srt[47])   # nearest-rank, 48th of 50

# --- 3. cold start: rm + run -d + poll until /health = 200 (5 samples)
$cold = 1..5 | ForEach-Object {
    docker rm -f $name 2>$null | Out-Null
    $sw = [Diagnostics.Stopwatch]::StartNew()
    docker run -d --name $name -p "${port}:8080" $image | Out-Null
    $ok = $false
    while (-not $ok) {
        $code = & curl.exe -s -m 1 -o NUL -w "%{http_code}" $base 2>$null
        if ($code -eq "200") { $ok = $true }
        else { Start-Sleep -Milliseconds 5 }
    }
    $sw.Stop()
    [math]::Round($sw.Elapsed.TotalMilliseconds, 1)
}
$cs = $cold | Sort-Object
Write-Output ("cold_p50_ms={0:N1}" -f $cs[2])     # median of 5
Write-Output ("cold_all_ms=" + (($cold | ForEach-Object { "{0:N1}" -f $_ }) -join ", "))

docker rm -f $name | Out-Null
Write-Output "done."
