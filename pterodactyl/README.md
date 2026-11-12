# 🦅 Kazama Windows on Pterodactyl

[🇬🇧 English](README.md) · [🇮🇩 Bahasa Indonesia](README.id.md) · [← Back to the main README](../README.md)

Run **Kazama Windows RDP** as a server in your own [Pterodactyl](https://pterodactyl.io) panel with the ready-made egg
[`egg-kazama-windows.json`](egg-kazama-windows.json). You connect with **Windows App** over RDP — this is an RDP desktop, **not a VPS**.

> ⚠️ **Read the next section first.** A stock Pterodactyl node cannot run this image. The guide below tells you exactly what the node must allow, and what it costs in security. I have **not** been able to test it on a live Wings node — treat it as experimental.

---

## 1. Why a stock Wings node is not enough

Wings starts every server container with restrictions that Windows-in-QEMU cannot live with:

| Wings default | What Kazama Windows needs |
|---|---|
| Runs as an unprivileged user (UID 988) | **root** (QEMU, networking helpers) |
| **Read-only** root filesystem | writable `/run`, `/var`, `/oem` … |
| Dropped capabilities, `no-new-privileges` | `NET_ADMIN` is optional (falls back to user-mode networking) |
| No `/dev/kvm` | `/dev/kvm` is optional, but without it Windows runs on **software emulation** (very slow) |
| Only `/home/container` is persistent | persistent **`/storage`** (the Windows disk, ~20–30 GB) |

So the node needs three things, plus one optional upgrade:

1. 🔓 the server container runs as **root**
2. ✍️ the root filesystem is **writable**
3. 💾 a persistent **Mount** at `/storage`
4. ⚡ *(optional, big speed-up)* a **privileged** container on a host that has `/dev/kvm` → real KVM acceleration

**Use a dedicated node only.** Relaxing these settings removes the isolation that protects other servers and the host from a compromised container. Never do it on a node shared with people you do not fully trust.

---

## 2. Checklist

- [ ] Pterodactyl Panel + Wings node you administer (dedicated to this)
- [ ] Node with **≥ 6 GB RAM** free and **≥ 45 GB** disk
- [ ] Optional: host with KVM (`ls /dev/kvm` works on the node)
- [ ] Wings configured as described in step 4 (root + writable rootfs + allowed mount)
- [ ] The image published to GHCR (step 1)
- [ ] Ports **3389** (RDP) and optionally **8006** (web viewer — keep it private) free on the node IP

---

## 3. Step by step

### Step 1 — Publish the image

The egg pulls `ghcr.io/kazamaofficial-git/kazama-windows:latest`.

1. In the GitHub repository open **Actions → Publish image → Run workflow** (or push a tag like `v1.0.0`).
2. When it finishes, open the repository's **Packages → kazama-windows → Package settings** and set **Visibility: Public** so Wings can pull it without a login.

### Step 2 — Import the egg

1. Panel → **Admin → Nests** → pick (or create) a nest, e.g. *Kazama*.
2. **Import Egg** → upload [`egg-kazama-windows.json`](egg-kazama-windows.json) → choose the nest → **Import**.

### Step 3 — Create the persistent Mount

Windows must keep its disk across restarts.

1. On the node, create the folder and give it to the Wings user:

   ```bash
   sudo mkdir -p /var/lib/kazama-windows
   sudo chown -R pterodactyl:pterodactyl /var/lib/kazama-windows   # use root:root if your container runs as root
   ```
2. Edit `/etc/pterodactyl/config.yml` on the node and allow the path:

   ```yaml
   allowed_mounts:
     - /var/lib/kazama-windows
   ```
3. Restart Wings: `sudo systemctl restart wings`.
4. Panel → **Admin → Mounts → Create New**:
   - **Name:** `kazama-windows-storage`
   - **Source:** `/var/lib/kazama-windows`
   - **Target:** `/storage`
   - **Read only:** off
   - After saving, open the mount and attach it to the **Kazama Windows RDP** egg and your **node**.

> A Mount has one fixed source folder. For several Windows servers, create one mount per server and attach each to its own server instead of the whole egg.

### Step 4 — Allow root + writable rootfs on the node (dedicated nodes only)

Stock Wings builds the container with a non-root user, a read-only root filesystem and `no-new-privileges`. Community guides relax this by building Wings from source and changing the container host configuration in `environment/docker/container.go` (line numbers differ per Wings version):

1. Run the container as root (set the container user to `0:0`).
2. Remove the `SecurityOpt: []string{"no-new-privileges"}` line.
3. Change `ReadonlyRootfs: true` to `ReadonlyRootfs: false`.
4. *(Optional, for KVM)* add `Privileged: true`. A privileged container sees the host's `/dev/kvm` and gets `NET_ADMIN`, so Windows then runs with **KVM acceleration** instead of emulation.

Then `go build`, replace the Wings binary and restart it. Do this only if you understand the security impact (see section 1). I could not verify these edits against your Wings version.

### Step 5 — Allocations (ports)

Pterodactyl publishes an allocation as the **same port number** on the host and inside the container, and Windows listens on **3389** inside the container. So:

- Make **3389** the **primary allocation** of the server (create the allocation under **Admin → Nodes → your node → Allocation**).
- Optional: add **8006** as an additional allocation for the web viewer — only reachable by you (firewall it), because it has no password.
- Prefer **Tailscale** (set `TAILSCALE_AUTHKEY`): then you do not need to expose 3389 at all.

If the node IP already uses port 3389, give the node another IP/alias and allocate 3389 on that one.

### Step 6 — Create the server

**Admin → Servers → Create New:**

| Field | Value |
|---|---|
| Egg | **Kazama Windows RDP** |
| Docker image | `Kazama Windows (latest)` |
| Memory | **at least `RAM_SIZE` + 1 GB** (e.g. `5120` MB for the default 4G) |
| CPU | e.g. `200`% for 2 cores |
| Disk | **≥ 45000 MB** |
| Swap | `0` |
| Primary allocation | the one with port **3389** |
| `RDP_PASSWORD` | your strong password (required) |
| Other variables | see the table below |

### Step 7 — Start and wait

Start the server and watch the console. The first boot **downloads and installs Windows** — without KVM this can take **hours**. Red lines such as *"KVM acceleration is not available"* or *"failed to create bridge … NET_ADMIN"* are **warnings, not crashes**: installation continues with software emulation and user-mode networking.

### Step 8 — Connect

**Windows App → + → PC:** PC name `<node-ip>:3389` (or your Tailscale IP/name), user account `RDP_USERNAME` / `RDP_PASSWORD`, then accept the certificate prompt.

---

## 4. Variables

| Variable | Default | Description |
|---|---|---|
| `RDP_PASSWORD` | — (required) | Windows user password. 8+ chars, 3 of lower/UPPER/digits/symbols, **no spaces or `< > & " '`**, must not contain the username. |
| `RDP_USERNAME` | `kazama` | Administrator account created at install. |
| `WINDOWS_VERSION` | `windows-latest` | `windows-latest` (Server 2025), `windows-2025`, `windows-2022`. |
| `RAM_SIZE` | `4G` | RAM for Windows (must fit the server's memory limit). |
| `CPU_CORES` | `2` | vCPU cores for Windows. |
| `DISK_SIZE` | `40G` | Virtual disk size (must fit the `/storage` mount). |
| `APP_LANG` | `en` | Log language: `en` or `id`. |
| `TAILSCALE_AUTHKEY` | — | Reusable + ephemeral key → private RDP over Tailscale. |
| `TAILSCALE_HOSTNAME` | `kazama-windows` | Machine name in your tailnet. |
| `BOOSTER_MODE` | `safe` | Storage Booster in Windows: `off`, `safe`, `deep`, `max` (see the main README). |
| `BOOSTER_SCHEDULE` | `weekly` | `off`, `daily`, `weekly` (03:00). |
| `BOOSTER_KEEP` | `chrome` | Catalog ids that `max` must not remove, e.g. `chrome,visualstudio`. |
| `KAZAMA_WALLPAPER` | `true` | Apply the Kazama wallpaper on first logon. |
| `KAZAMA_TUNE` | `light` | Performance tuning for emulation: `off`, `light`, `max`. |

`RDP_PASSWORD`, `RDP_USERNAME`, `WINDOWS_VERSION` and the booster/tune/wallpaper settings apply **only at the first install**. To change the password later do it inside Windows; to change the Windows version, empty the `/storage` folder and reinstall.

---

## 5. Stopping

The egg stops the server with `^C` (SIGINT); the image then asks Windows to shut down. A clean Windows shutdown can take up to about 2 minutes. If your Wings version kills the container sooner, shut Windows down from inside the RDP session (Start → Power → Shut down) **before** stopping the server, otherwise the disk can be left in an unclean state.

---

## 6. Troubleshooting

| Problem | Likely cause / fix |
|---|---|
| Container exits at once with a permission or "read-only file system" error | The node still runs containers as non-root / with a read-only root filesystem — step 4. |
| Image cannot be pulled | The GHCR package is not public (step 1) or the Publish workflow has not run yet. |
| Windows installs again after every restart | The `/storage` Mount is missing or not attached to the egg/server (step 3). |
| Console shows `RDP_PASSWORD is required` / password error | Fix the variable; the rules are listed in section 4. |
| Cannot connect over RDP | Wait until Windows finished installing; make sure the 3389 allocation is the primary one and the firewall allows it — or use Tailscale. |
| Extremely slow | No KVM. Use a node with `/dev/kvm` + a privileged container (step 4), or set `KAZAMA_TUNE=light`/`max`. |
| `RDP_PASSWORD` change has no effect | It applies at first install only — change it inside Windows. |

---

## 7. Security

- Anyone who can reach RDP can try to log in: use a long, unique password and prefer **Tailscale**.
- Do **not** expose port 8006 publicly; the web viewer has no password.
- Relaxing Wings (root, writable root filesystem, privileged) weakens isolation — dedicated node only.

---

<p align="center">
  © Kazama Tech · Developed by <a href="https://github.com/kazamaofficial-git"><b>@kazamaofficial-git</b></a>
</p>
