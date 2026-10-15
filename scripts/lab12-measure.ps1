# Lab 12 — measurement script (run from the repo root on Windows):
#   powershell -ExecutionPolicy Bypass -File scripts\lab12-measure.ps1
#
# Requires on PATH: spin.exe (4.2.x), wasmtime.exe, hyperfine.exe, docker, curl.exe.
# No build toolchain needed: wasm/main.wasm is committed.
# Writes evidence to submissions/lab12-artifacts/.
param(
  [string]$Spin = "spin",
  [string]$Wasmtime = "wasmtime",
  [string]$Hyperfine = "hyperfine",
  [string]$Image = "ghcr.io/nikolaytaran/devops-intro/quicknotes:v0.1.0",
  [int]$SpinPort = 3000,
  [int]$DockerPort = 18080
)
$ErrorActionPreference = "Continue"
$art = "submissions/lab12-artifacts"
New-Item -ItemType Directory -Force -Path $art | Out-Null
$spinUrl = "http://127.0.0.1:$SpinPort/time"
$dkUrl = "http://127.0.0.1:$DockerPort/health"
$cold = "$art/cold-start.txt"
"" | Out-File $cold

function Wait-Url([string]$url, [int]$timeoutSec = 90) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $timeoutSec) {
    $code = & curl.exe -s -o NUL -w "%{http_code}" $url 2>$null
    if ($code -eq "200") { return $sw.Elapsed.TotalMilliseconds }
    Start-Sleep -Milliseconds 100
  }
  throw "timeout waiting for 200 on $url"
}

Write-Host "== versions =="
& $Spin --version  2>&1 | Out-File "$art/versions.txt"
& $Wasmtime --version 2>&1 | Add-Content "$art/versions.txt"
& $Hyperfine --version 2>&1 | Add-Content "$art/versions.txt"
docker version --format "docker {{.Server.Version}}" 2>&1 | Add-Content "$art/versions.txt"
Get-Content "$art/versions.txt"

Write-Host "== 1) start Spin (warm-up run, first start to 200) =="
taskkill /IM spin.exe /F 2>$null | Out-Null
$spinProc = Start-Process -FilePath $Spin -ArgumentList "up", "--listen", "127.0.0.1:$SpinPort" -WorkingDirectory "wasm" -PassThru -NoNewWindow
$t = Wait-Url $spinUrl
("spin first start -> 200: {0:N0} ms" -f $t) | Tee-Object "$art/spin-up.txt"

Write-Host "== 2) /time response (evidence) =="
curl.exe -s $spinUrl | Tee-Object "$art/curl-time.json"
Write-Host ""

Write-Host "== 3) warm latency: hyperfine 50 runs, Spin /time =="
& $Hyperfine --warmup 5 --runs 50 --export-json "$art/hyperfine-spin.json" "curl.exe -s -o NUL $spinUrl" 2>&1 | Tee-Object "$art/hyperfine-warm.txt"

Write-Host "== 4) Docker baseline: start Lab 6 image =="
docker rm -f qn-lab12 2>$null | Out-Null
$dkStart = [Diagnostics.Stopwatch]::StartNew()
docker run -d --rm --name qn-lab12 -p "${DockerPort}:8080" $Image | Out-Null
$dkCold1 = Wait-Url $dkUrl
("docker first start -> 200 (incl. docker run): {0:N0} ms" -f $dkCold1) | Tee-Object "$art/docker-up.txt"

Write-Host "== 5) warm latency: hyperfine 50 runs, Docker /health =="
& $Hyperfine --warmup 5 --runs 50 --export-json "$art/hyperfine-docker.json" "curl.exe -s -o NUL $dkUrl" 2>&1 | Tee-Object "$art/hyperfine-warm.txt" -Append

Write-Host "== 6) cold starts, 5 samples each =="
# Docker: fresh container each time
1..5 | ForEach-Object {
  docker rm -f qn-lab12 2>$null | Out-Null
  Start-Sleep -Milliseconds 300
  $sw = [Diagnostics.Stopwatch]::StartNew()
  docker run -d --rm --name qn-lab12 -p "${DockerPort}:8080" $Image | Out-Null
  $t = Wait-Url $dkUrl 120
  ("docker cold #{0}: {1:N0} ms" -f $_, $t) | Tee-Object $cold -Append
} | Out-Null
docker rm -f qn-lab12 2>$null | Out-Null

# Spin: kill the runtime, restart, wait for first 200
1..5 | ForEach-Object {
  taskkill /IM spin.exe /F 2>$null | Out-Null
  Start-Sleep -Milliseconds 300
  $spinProc = Start-Process -FilePath $Spin -ArgumentList "up", "--listen", "127.0.0.1:$SpinPort" -WorkingDirectory "wasm" -PassThru -NoNewWindow
  $t = Wait-Url $spinUrl 120
  ("spin cold #{0}: {1:N0} ms" -f $_, $t) | Tee-Object $cold -Append
} | Out-Null

Write-Host "== 7) artifact sizes =="
"main.wasm: {0} bytes" -f (Get-Item "wasm/main.wasm").Length | Tee-Object "$art/sizes.txt"
"wasm-cli/main.wasm: {0} bytes" -f (Get-Item "wasm-cli/main.wasm").Length | Add-Content "$art/sizes.txt"
docker images --format "{{.Repository}}:{{.Tag}} {{.Size}}" | Select-String "quicknotes" | ForEach-Object { $_.Line } | Add-Content "$art/sizes.txt"
Get-Content "$art/sizes.txt"

Write-Host "== 8) bonus: wasmtime per-invocation, 10 runs =="
1..10 | ForEach-Object {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  & $Wasmtime run --env REQUEST_METHOD=GET --env PATH_INFO=/time "wasm-cli/main.wasm" | Out-File "$art/wasmtime-run.txt" -Append
  ("wasmtime run #{0}: {1:N0} ms" -f $_, $sw.Elapsed.TotalMilliseconds) | Tee-Object $cold -Append
} | Out-Null

Write-Host "== cleanup =="
taskkill /IM spin.exe /F 2>$null | Out-Null
Write-Host "Done. Artifacts in $art"
