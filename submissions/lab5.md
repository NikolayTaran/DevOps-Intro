# Lab 5 — Virtualization: QuickNotes in a Vagrant VM

**Student:** NikolayTaran (na.taranvrn@gmail.com)
**Fork:** https://github.com/NikolayTaran/DevOps-Intro
**Branch:** `feature/lab5`
**PR (course repo):** https://github.com/inno-devops-labs/DevOps-Intro/pull/1632
**Host:** Windows 11 · VirtualBox 7.1.x · Vagrant 2.4.x
**Box:** `bento/ubuntu-24.04` (Ubuntu 24.04.3 LTS, public bento project)
**VM profile:** `quicknotes-lab5` — 2 vCPU · 1024 MB RAM · NAT · `127.0.0.1:18080 → guest 8080` · `app/` rsynced to `/home/vagrant/quicknotes`

> **Host note (it explains every timing below).** Windows was silently running its own hypervisor, so VirtualBox had to emulate through it: the first `vagrant up` timed out waiting for SSH while the guest console showed `systemd-networkd` grinding in a 6-minute start window and `rcu_preempt` CPU stalls — 5–10 minute boots. Disabling Hyper-V (`bcdedit /set hypervisorlaunchtype off`) removed the root cause; every boot after that completes well inside Vagrant's SSH timeout. The lab's pitfall list literally says *"On Windows make sure Hyper-V is disabled"* — now it is.

---

## Task 1 — Vagrant Up + Run QuickNotes Inside (6 pts)

### 1.1: How every requirement is met

| Requirement | Where it lives |
|---|---|
| **Box:** Ubuntu 22.04/24.04 LTS from a public source | `config.vm.box = "bento/ubuntu-24.04"` — Ubuntu 24.04.3 LTS built by the public bento project, taken from the HCP Vagrant catalog |
| **Hostname** identifies QuickNotes | `config.vm.hostname = "quicknotes-lab5"` (verified from inside: `vagrant ssh -c hostname` → `quicknotes-lab5`) |
| **Port forwarding** host **18080** → guest **8080**, loopback only | `config.vm.network "forwarded_port", guest: 8080, host: 18080, host_ip: "127.0.0.1"` |
| **Synced folder:** host `./app` into the guest | `config.vm.synced_folder "app", "/home/vagrant/quicknotes", type: "rsync", rsync__exclude: [".git/", "bin/", "tmp/"]` |
| **Resources:** 2 vCPU / 1024 MB | `vb.cpus = 2`, `vb.memory = 1024` in the `virtualbox` provider block |
| **Provisioning:** Go 1.24.x installed during `vagrant up` | `config.vm.provision "shell", path: "scripts/install-go.sh"` — pinned Go **1.24.5** tarball from `go.dev/dl`, idempotent (exact-version guard) |
| **Reproducible** from a clean clone | box pinned by name, toolchain pinned to one exact tarball URL, provisioner is a no-op when that version is already present, code comes from the repo itself via rsync — `git clone && vagrant up` lands on the same working state |

The full `Vagrantfile` is in **Appendix A**; the provisioner script is [`scripts/install-go.sh`](../scripts/install-go.sh) (behavior described in **Appendix B**).

### 1.2: `vagrant up` + provisioning evidence

Clean `vagrant up --provision` after the Hyper-V fix — boot, rsync and the provisioner's idempotency guard in a single run:

```
C:\Users\Inno\OneDrive\Documents\DevOps-Intro>vagrant up --provision
Bringing machine 'default' up with 'virtualbox' provider...
==> default: Clearing any previously set forwarded ports...
==> default: Clearing any previously set network interfaces...
==> default: Preparing network interfaces based on configuration...
    default: Adapter 1: nat
==> default: Forwarding ports...
    default: 8080 (guest) => 18080 (host) (adapter 1)
    default: 22 (guest) => 2222 (host) (adapter 1)
==> default: Running 'pre-boot' VM customizations...
==> default: Booting VM...
==> default: Waiting for machine to boot. This may take a few minutes...
    default: SSH address: 127.0.0.1:2222
    default: SSH username: vagrant
    default: SSH auth method: private key
==> default: Machine booted and ready!
==> default: Checking for guest additions in VM...
==> default: Setting hostname...
==> default: Rsyncing folder: /cygdrive/c/Users/Inno/OneDrive/Documents/DevOps-Intro/app/ => /home/vagrant/quicknotes
==> default:   - Exclude: [".vagrant/", ".git/", "bin/", "tmp/"]
==> default: Running provisioner: shell...
    default: ==> Go 1.24.5 already installed: go version go1.24.5 linux/amd64. Skipping.
```

(The `Mounting shared folders ... => /vagrant` line that follows is Vagrant's built-in default share of the repo root; the application code lives on the dedicated rsync share above.)

The provisioner's **first-ever** run — the one that actually installed Go — printed:

```
default: ==> Installing base packages
default: Get:1 http://security.ubuntu.com/ubuntu noble-security InRelease [126 kB]
default: ...
default: git is already the newest version (1:2.43.0-1ubuntu7.3).
default: The following packages will be upgraded: ca-certificates curl libcurl3t64-gnutls libcurl4t64 rsync
default: ...
default: ==> Downloading https://go.dev/dl/go1.24.5.linux-amd64.tar.gz
default: ==> Extracting to /usr/local
default: ==> Installed: go version go1.24.5 linux/amd64
```

Re-running the provisioner is a **no-op**: the guard checks the exact toolchain version and skips the download — that is both the lab guideline *"test idempotency before submitting"* and reproducibility (requirement 7) demonstrated live. Screenshot: `submissions/screenshots/02-vagrant-up-output.png`.

Note on the log: no `Importing base box` lines appear because the VM had already been created by the first `vagrant up`; the box itself was registered in the local catalog as `bento/ubuntu-24.04` (the catalog's file CDN returned 404 from my network, so the box file was added via `vagrant box add` — metadata resolved fine, only the file download was affected).

### 1.3: Verify — Go inside the VM, code synced

```
C:\Users\Inno\OneDrive\Documents\DevOps-Intro>vagrant ssh -c "go version"
go version go1.24.5 linux/amd64

C:\Users\Inno\OneDrive\Documents\DevOps-Intro>vagrant ssh -c "hostname && ls -la /home/vagrant/quicknotes"
quicknotes-lab5
total 9768
drwxr-xr-x 2 vagrant vagrant    4096 Sep 17 23:47 .
drwxr-x--- 6 vagrant vagrant    4096 Sep 23 12:04 ..
-rw-r--r-- 1 vagrant vagrant     158 Sep 10 09:29 .golangci.yml
-rw-r--r-- 1 vagrant vagrant      30 Sep 10 09:29 go.mod
-rw-r--r-- 1 vagrant vagrant    4962 Sep 10 09:29 handlers.go
-rw-r--r-- 1 vagrant vagrant    3604 Sep 16 23:50 handlers_test.go
-rw-r--r-- 1 vagrant vagrant    1858 Sep 10 09:29 main.go
-rw-r--r-- 1 vagrant vagrant     345 Sep 10 09:29 Makefile
-rwxr-xr-x 1 vagrant vagrant 9947136 Sep 10 12:59 quicknotes.exe
-rw-r--r-- 1 vagrant vagrant    1194 Sep 10 13:00 README.md
-rw-r--r-- 1 vagrant vagrant     782 Sep 10 09:29 seed.json
-rw-r--r-- 1 vagrant vagrant    2371 Sep 10 09:29 store.go
-rw-r--r-- 1 vagrant vagrant    1899 Sep 10 09:29 store_test.go
```

`quicknotes-lab5` hostname + the complete QuickNotes source tree inside the guest — requirements 2 and 4 proven in one command. Screenshots: `03-go-version-vm.png`, `04-synced-folder-vm.png`.

### 1.4: Verify — QuickNotes running inside, reachable from the host

Inside the VM — build, run in the background, curl the guest locally on `:8080`:

```
vagrant@quicknotes-lab5:~$ cd /home/vagrant/quicknotes
vagrant@quicknotes-lab5:~/quicknotes$ go build -o /tmp/qn .
vagrant@quicknotes-lab5:~/quicknotes$ nohup /tmp/qn > /tmp/qn.log 2>&1 &
[1] 2989
vagrant@quicknotes-lab5:~/quicknotes$ sleep 2
vagrant@quicknotes-lab5:~/quicknotes$ curl -s http://127.0.0.1:8080/health
{"notes":4,"status":"ok"}
```

From the **host** through the forwarded port (`curl.exe -i` so the status line is visible; PowerShell's `curl` is an alias for `Invoke-WebRequest`, hence `curl.exe`):

```
C:\Users\Inno\OneDrive\Documents\DevOps-Intro>curl.exe -i http://127.0.0.1:18080/health
HTTP/1.1 200 OK
Content-Type: application/json
Date: Wed, 23 Sep 2026 12:38:24 GMT
Content-Length: 26

{"notes":4,"status":"ok"}
```

`HTTP/1.1 200 OK` — the host reached into the guest via `127.0.0.1:18080` and QuickNotes answered. That is the Task 1 acceptance criterion. Screenshots: `05-build-run-inside-vm.png`, `06-health-from-host.png`.

### 1.5: Design questions

**a) Synced folders: `nfs`, `rsync`, `virtualbox`, `smb` — which did I pick and why? What's the trade-off?**
I picked **rsync**. First, it has no Guest Additions dependency: Vagrant drives it over the same SSH connection it already uses, so the folder behaves identically on any box and any host OS. Second, its one-way (host → guest) direction matches the real workflow: the Windows repo is the source of truth, the VM is a disposable runtime — bidirectionality would only add ways for the two copies to diverge. Third, `rsync__exclude` keeps host-side artifacts (`.git/`, `bin/`, `tmp/`) out of the guest. The trade-off: it is **not live** — the guest is updated at `up`/`reload`/`rsync` only, and guest-side writes (QuickNotes creates `data/notes.json` in there) never flow back to the host; after editing code you re-sync, you don't hot-reload. A `virtualbox` shared folder is bidirectional and live but requires Guest Additions inside the box and has long-standing symlink/mtime quirks; `smb` drags Windows credentials and file-locking semantics into the mix; `nfs` on a Windows host is impractical (no NFS server Vagrant can drive without extra software). For "host writes code, guest runs it" rsync is the deterministic, lowest-magic choice.

**b) NAT vs Bridged vs Host-only: which network mode, and why is `127.0.0.1`-bound forwarding safer than Bridged here?**
**NAT** — Vagrant's default, and what my forward rides on: the VM has no routable LAN IP; all host→guest traffic goes through VirtualBox's NAT engine (SSH on `127.0.0.1:2222 → 22`, QuickNotes on `127.0.0.1:18080 → 8080`). With `host_ip: "127.0.0.1"` the published port is bound to the host's loopback interface, so only processes on this same machine can reach it — a port scan from another laptop on the same Wi-Fi sees nothing at all. A **Bridged** adapter would put the VM on the physical network with its own LAN IP, and QuickNotes would accept connections from everyone in the coffee shop / dorm network; a course exercise doesn't need that attack surface. Host-only would also work (private subnet between host and VM) but needs its own network interface and firewall reasoning, while NAT+loopback is the smallest, default-shaped blast radius — the VM stays an appliance *behind* the host, not a first-class network citizen.

**c) Provisioning options: which did I pick and why?**
**shell.** Installing one pinned tarball is ~20 lines of bash; a full config-management system (Puppet, Chef) or even Ansible would add an agent/control-node/Python dependency chain to a problem this size. The shell provisioner needs nothing but the SSH channel Vagrant already has, it runs automatically during `vagrant up` (requirement 6: no student ever SSHes in to install Go), the script is versioned in the same repo as the Vagrantfile, and I made it **idempotent** with an exact-version guard so `vagrant provision` re-runs are safe no-ops (shown in 1.2). There is also a forward-compatibility argument: Lab 7 targets this same VM with an Ansible playbook — shell now, `ansible_local` later, no wasted effort.

**d) Why pin Go to `1.24.5` instead of `1.24`?**
Because `1.24` is a **moving pointer**, not a version. A script that installs "1.24" resolves to whatever patch release is current at the moment it runs — 1.24.1 today, 1.24.9 next month — with different bugfixes, stdlib behavior and toolchain quirks. `vagrant up` from a clean clone would then produce a *different* machine every week, silently, and a bug report becomes unreproducible because the environment no longer exists. Pinning `1.24.5` freezes the exact tarball URL, so every host downloads a bit-identical toolchain, and upgrading becomes a deliberate, reviewable diff (`1.24.5` → `1.24.6` in one commit). It is the same principle as SHA-pinning GitHub Actions in Lab 3: reproducibility requires immutable references, and "latest patch" is not one.

---

## Task 2 — Snapshots: Save, Break, Restore (4 pts)

### 2.1: Required actions — commands

**1) Snapshot of the working VM:**

```
C:\Users\Inno\OneDrive\Documents\DevOps-Intro>vagrant snapshot save clean-lab5
==> default: Snapshotting the machine as 'clean-lab5'...
==> default: Snapshot saved! You can restore the snapshot at any time by
==> default: using `vagrant snapshot restore`. You can delete it using
==> default: `vagrant snapshot delete`.

C:\Users\Inno\OneDrive\Documents\DevOps-Intro>vagrant snapshot list
==> default:
clean-lab5
```

**2) Break the VM deliberately** — wipe the pinned Go toolchain (the thing requirement 6 installed):

```
C:\Users\Inno\OneDrive\Documents\DevOps-Intro>vagrant ssh -c "sudo rm -rf /usr/local/go /usr/local/bin/go /usr/local/bin/gofmt"
```

**3) Verify it's broken:**

```
C:\Users\Inno\OneDrive\Documents\DevOps-Intro>vagrant ssh -c "go version"
bash: line 1: go: command not found
```

Screenshot: `08-broken-go.png` — the toolchain requirement 6 installed is gone; `go` doesn't even resolve on `PATH`.

**4) Restore, timed** (`Measure-Command` is PowerShell's equivalent of bash `time`; it swallows Vagrant's progress output, so the console stays silent until the timing prints):

```powershell
C:\Users\Inno\OneDrive\Documents\DevOps-Intro>powershell -Command "Measure-Command { vagrant snapshot restore clean-lab5 }"

Days              : 0
Hours             : 0
Minutes           : 0
Seconds           : 33
Milliseconds      : 797
Ticks             : 337976962
TotalDays         : 0,000391177039351852
TotalHours        : 0,00938824894444444
TotalMinutes      : 0,563294936666667
TotalSeconds      : 33,7976962
TotalMilliseconds : 33797,6962
```

Wall-clock for the whole cycle — power off the running VM, rewind the disk to the snapshot's block state, boot again, SSH ready — is **33.8 s**, right on the lab Overview's promise of *"a 'clean' snapshot you can roll back to in 30 seconds"*. Screenshot: `09-snapshot-restore-time.png`.

Worth stating what a restore does **and does not** do: the disk returns to the snapshotted state (Go is back, exactly as pinned), but **no processes come back** — after a restore QuickNotes is not running and has to be started again. Snapshots rewind state, not runtime.

**5) Verify recovery:**

```
C:\Users\Inno\OneDrive\Documents\DevOps-Intro>vagrant ssh -c "go version"
go version go1.24.5 linux/amd64
```

The broken thing works again — same pinned version, restored from the delta in half a minute. Screenshot: `10-restored-go.png`.

### 2.2: Design questions

**e) Snapshots are not backups — why, and which failure modes make them useless?**
A snapshot is a **delta chain recorded on the same virtual disk, on the same physical host, managed by the same VirtualBox installation**. It rolls back logical mistakes ("I deleted `/usr/local/go`", "I broke the config") by rewinding that disk's block state — but it shares the fate of everything it depends on: the host disk dies → snapshot and original die together; the VM folder is deleted or encrypted by ransomware → gone; the VirtualBox/Vagrant metadata is corrupted → the chain is unopenable; the laptop is stolen → both are in the bag. A backup, by contrast, is a **full, independent copy stored on different media**, and it survives precisely those failure modes that a snapshot cannot. Snapshot = undo for the guest's *logical* state; backup = insurance for the *physical* substrate.

**f) Copy-on-write: what does taking 10 snapshots vs 1 mean for disk usage?**
VirtualBox snapshots are copy-on-write: taking one **freezes the current disk state** (the base becomes read-only for that lineage) and redirects all subsequent writes into a fresh delta file. One snapshot = base + 1 delta holding only the blocks changed since. Ten snapshots = base + a chain of 10 deltas, each recording only *its* changed blocks — so an idle disk grows slowly, and total size stays modest **as long as the machine doesn't diverge much from the snapshot points**. But the deltas accumulate and never shrink: every block touched after snapshot N lives in delta N and everything later, deleted data is not reclaimed, and each additional snapshot adds another layer of bookkeeping the hypervisor must walk on every read of an old block. Ten snapshots ≠ 10 full disks, but it is base + N growing layers — and deleting a snapshot in the middle means merging its delta into the next one, which is why chain depth is the real cost driver.

**g) When is snapshotting an antipattern?**
**Long chains.** If "we'll just snapshot before every experiment" becomes the workflow, you end up with a deep dependency graph: each restore/delete must traverse (or merge) every delta below it, so operations get slower the more you "protect" yourself; disk usage creeps toward and past the base image; and a single corrupted delta silently invalidates every snapshot taken after it. It also creates a false sense of safety (see *e*) and hides configuration drift: nobody knows which "clean" state the 12th snapshot actually represents. The sustainable pattern is the one this lab already uses: **one meaningful, named checkpoint** (`clean-lab5`) plus the real rollback mechanism — the Vagrantfile + provisioner, i.e. `vagrant destroy && vagrant up` rebuilds a known-good machine from source. Snapshots are a short-term undo; infrastructure-as-code is the lifecycle tool. Cattle, not pets.

---

## Bonus — VM vs Container Resource Baseline (2 pts)

**Methodology.** Both baselines were taken on the **same laptop on the same day**; the only thing between them is the hypervisor switch the two stacks require on Windows (Hyper-V off for VirtualBox, back on for Docker Desktop) plus one reboot — no hardware, load or config changes. Both sides are *idle* numbers: the VM was measured right after a plain `vagrant up` (provisioner skipped, QuickNotes not yet started), the container after it answered `curl` and was itself stopped/started.

### B.1: VM baseline (VirtualBox, Hyper-V off)

```
C:\Users\Inno\OneDrive\Documents\DevOps-Intro>powershell -Command "Measure-Command { vagrant halt }"
Days              : 0
Hours             : 0
Minutes           : 0
Seconds           : 15
Milliseconds      : 102
...
TotalMilliseconds : 15102,9603          → halt = 15.1 s

C:\Users\Inno\OneDrive\Documents\DevOps-Intro>powershell -Command "Measure-Command { vagrant up }"
Days              : 0
Hours             : 0
Minutes           : 0
Seconds           : 58
Milliseconds      : 168
...
TotalMilliseconds : 58168,708           → cold boot = 58.2 s (no provisioning — skipped as "already provisioned")

C:\Users\Inno\OneDrive\Documents\DevOps-Intro>vagrant ssh -c "free -h"
               total        used        free      shared  buff/cache   available
Mem:           961Mi       321Mi       551Mi       1.0Mi       229Mi       639Mi
Swap:          2.9Gi          0B       2.9Gi

C:\Users\Inno\OneDrive\Documents\DevOps-Intro>vagrant ssh -c "ps -A --no-headers | wc -l"
149

C:\Users\Inno\OneDrive\Documents\DevOps-Intro>powershell -Command "[math]::Round((Get-ChildItem -Recurse -Force \"$env:USERPROFILE\VirtualBox VMs\quicknotes-lab5\" | Measure-Object Length -Sum).Sum / 1GB, 2)"
2,9                                     → VM image on disk = 2.9 GB (incl. the clean-lab5 snapshot delta)
```

### B.2: Container baseline (Docker Desktop, same host)

```
C:\Users\Inno\OneDrive\Documents\DevOps-Intro>docker run -d --name qn-lab5 -p 28080:8080 -v "%cd%\app:/src" -w /src golang:1.24 sh -c "go build -o /tmp/qn && /tmp/qn"
b6e1146476b0...

C:\Users\Inno\OneDrive\Documents\DevOps-Intro>curl.exe -i http://127.0.0.1:28080/health
HTTP/1.1 200 OK
Content-Type: application/json
Date: Wed, 23 Sep 2026 13:52:19 GMT
Content-Length: 26

{"notes":4,"status":"ok"}

C:\Users\Inno\OneDrive\Documents\DevOps-Intro>docker stop qn-lab5
qn-lab5

C:\Users\Inno\OneDrive\Documents\DevOps-Intro>powershell -Command "Measure-Command { docker start qn-lab5 }"
Days              : 0
Hours             : 0
Minutes           : 0
Seconds           : 0
Milliseconds      : 311
...
TotalMilliseconds : 311,5454            → cold start = 0.31 s

C:\Users\Inno\OneDrive\Documents\DevOps-Intro>docker stats --no-stream
CONTAINER ID   NAME      CPU %   MEM USAGE / LIMIT    MEM %   NET I/O         BLOCK I/O   PIDS
b6e1146476b0   qn-lab5   0.00%   8.52MiB / 7.411GiB   0.11%   1.17kB / 126B   0B / 0B     10

C:\Users\Inno\OneDrive\Documents\DevOps-Intro>docker top qn-lab5
UID    PID    PPID   C    STIME   TTY   TIME      CMD
root   2465   ...    0    13:52   ?     00:00:00  sh -c go build -o /tmp/qn && /tmp/qn
root   2610   2465   0    13:52   ?     00:00:00  /tmp/qn
                                          → 2 processes total

C:\Users\Inno\OneDrive\Documents\DevOps-Intro>docker images golang:1.24
IMAGE        ID            DISK USAGE   CONTENT SIZE
golang:1.24  d2d2bc1c84f7  1.32GB       335MB
```

(`PIDS 10` in `docker stats` counts the Go runtime's threads inside the cgroup; the process view in `docker top` shows the 2 actual processes.)

### B.3: The comparison

| Dimension | Vagrant VM | Docker container |
|---|---:|---:|
| Cold start | **73.3 s** (15.1 s halt + 58.2 s boot) | **0.31 s** (`docker start`) — two orders of magnitude |
| Idle RAM | **321 MiB** used of 961 MiB (639 MiB available) | **8.52 MiB** of a 7.41 GiB limit — ~38× lighter |
| On-disk size | **2.9 GB** (VM folder incl. snapshot delta) | **1.32 GB** image (335 MB compressed content) — ~2.2× |
| Process count (guest) | **149** | **2** — ~75× fewer |

**Analysis.** The surprise is not that the container is lighter — it is *how categorically* lighter: cold start 0.31 s vs 73.3 s (two orders of magnitude) and idle RAM 8.5 MiB vs 321 MiB (~38×) are not tuning margins but different classes of machines. The mechanism is visible in the last row: the VM spends its 58 seconds booting a guest kernel plus the 149 processes systemd stands up before any application runs, while the container is just 2 user-space processes (`sh` waiting on `/tmp/qn`) sharing the host's already-running kernel — there is simply nothing to boot. Each model owns a different territory: the VM is the right tool when you need a different OS or kernel, hard tenant isolation, or a stable appliance to provision, snapshot and roll back (exactly this lab, and Lab 7's Ansible target), while containers win for dense, stateless, horizontally-scaled services whose instances are disposable. That is the data behind containers winning 2014–2020 for stateless microservices: a ~38× RAM advantage turns a node that fits 3 VMs into one that fits dozens of containers, sub-second starts make autoscaling and rolling deploys effectively instantaneous, and with per-instance cost near zero, 'delete and recreate' (cattle, not pets) becomes the default recovery strategy instead of repair. The one number keeping containers honest is disk — 1.32 GB vs 2.9 GB is only ~2× — but that image is paid once and shared by every container on the host, so the marginal cost of the n+1-th service still tends to zero.

---

## Appendix A — `Vagrantfile`

```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-24.04"
  config.vm.hostname = "quicknotes-lab5"

  config.vm.network "forwarded_port",
    guest: 8080, host: 18080, host_ip: "127.0.0.1"

  config.vm.synced_folder "app", "/home/vagrant/quicknotes",
    type: "rsync",
    rsync__exclude: [".git/", "bin/", "tmp/"]

  config.vm.provider "virtualbox" do |vb|
    vb.name   = "quicknotes-lab5"
    vb.cpus   = 2
    vb.memory = 1024
  end

  config.vm.provision "shell", path: "scripts/install-go.sh"

  config.vm.post_up_message = <<~MSG
    QuickNotes VM is up!
      Go:     vagrant ssh -c 'go version'
      Health: curl http://127.0.0.1:18080/health
  MSG
end
```

## Appendix B — `scripts/install-go.sh` (what it does)

The provisioner is [`scripts/install-go.sh`](../scripts/install-go.sh) in the repo root; in order:

1. **Idempotency guard** — if `go version` already reports `go1.24.5`, print `==> Go 1.24.5 already installed: ... Skipping.` and exit 0. This is what makes repeated `vagrant provision` runs safe (see 1.2).
2. `apt-get update` + install `curl ca-certificates git rsync` (rsync is needed by the synced folder itself; curl for the download).
3. Download the **pinned** tarball `https://go.dev/dl/go1.24.5.linux-amd64.tar.gz`.
4. `rm -rf /usr/local/go` + extract the tarball to `/usr/local` (clean re-extract keeps the step repeatable even without the guard).
5. Symlink `go` and `gofmt` into `/usr/local/bin` — so `vagrant ssh -c 'go version'` works without any PATH editing.
6. Drop `/etc/profile.d/go.sh` (adds `/usr/local/go/bin` to PATH for login shells).

## Screenshots

All in `submissions/screenshots/`:

- `01-vagrant-status.png` — `vagrant status`: `default  running (virtualbox)`
- `02-vagrant-up-output.png` — full `vagrant up --provision` log: boot → rsync → idempotent provisioner (`already installed ... Skipping`)
- `03-go-version-vm.png` — `vagrant ssh -c "go version"` → `go1.24.5 linux/amd64`
- `04-synced-folder-vm.png` — `hostname` (`quicknotes-lab5`) + QuickNotes source tree inside the guest
- `05-build-run-inside-vm.png` — build + background run + `curl` on guest `:8080` → `{"notes":4,"status":"ok"}`
- `06-health-from-host.png` — `curl.exe -i http://127.0.0.1:18080/health` → `HTTP/1.1 200 OK` + JSON
- `07-snapshot-save.png` — `vagrant snapshot save clean-lab5` → `Snapshot saved!` + `vagrant snapshot list` → `clean-lab5`
- `08-broken-go.png` — after wiping the toolchain: `bash: line 1: go: command not found`
- `09-snapshot-restore-time.png` — `Measure-Command` around the restore: **33.8 s**
- `10-restored-go.png` — after restore: `go version go1.24.5 linux/amd64` again
- `11-bonus-vm-baseline.png` — VM baseline: halt 15.1 s, boot 58.2 s, `free -h` (321 Mi used), 149 processes, 2.9 GB on disk
- `12-bonus-docker-baseline.png` — container baseline: `200 OK` + JSON, start 0.31 s, `docker stats` 8.52 MiB, `docker top` 2 processes, image 1.32 GB
