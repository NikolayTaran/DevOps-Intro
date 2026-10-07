# Teardown — Lab 10

Everything created for this lab is free-tier or ephemeral; nothing bills by default.

## Codespace (Option B environment)

```bash
# stop (keeps the environment, stops billing of core hours)
gh codespace stop -c crispy-guide-4x945xgrr7wh7wvq

# or delete completely
gh codespace delete -c crispy-guide-4x945xgrr7wh7wvq
```

Web UI equivalent: github.com/codespaces → `...` → Stop / Delete.

## Cloudflare quick tunnel

Nothing to tear down — quick tunnels are ephemeral and vanish when `cloudflared`
exits (Ctrl+C). No Cloudflare account was created, no DNS records exist.

## Local machine

```powershell
docker rm -f quicknotes-lab10     # bonus-era container from the ghcr image
docker rmi ghcr.io/nikolaytaran/devops-intro/quicknotes:v0.1.0   # optional
```

The Lab 6 `quicknotes-lab6` container was stopped (not removed) while the bonus
container occupied `:8080`; it was started back afterwards.

## Registry / repo artifacts

- GHCR package `ghcr.io/nikolaytaran/devops-intro/quicknotes` — **kept public**:
  it is the deliverable of Task 1 and the input the grader may pull.
- `v0.1.0` tag + green release run — kept (audit trail).
- If ever needed: package → GitHub UI → Package settings → Delete this package.
