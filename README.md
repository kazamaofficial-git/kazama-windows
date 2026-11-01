<p align="center">
  <img src="assets/wallpaper.png" alt="Kazama Windows" width="100%"/>
</p>

<h1 align="center">Kazama Windows — RDP 🪟</h1>

<p align="center">
  A Windows Server desktop you reach with <b>Windows App</b> over <b>RDP</b> — on <b>Railway</b> or on a <b>GitHub Actions</b> Windows runner.<br/>
  <b>This is an RDP desktop, not a VPS.</b>
</p>

<p align="center">
  🇬🇧 English &nbsp;·&nbsp; 🇮🇩 <a href="README.id.md">Bahasa Indonesia</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-Railway%20%7C%20GitHub%20Actions-0B0D0E" alt="Platforms">
  <img src="https://img.shields.io/badge/Windows-Server%202025%20%7C%202022-0078D4?logo=windows&logoColor=white" alt="Windows Server">
  <img src="https://img.shields.io/badge/access-RDP%20%2F%20Tailscale-6366f1" alt="RDP">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License">
</p>

---

## Choose your mode

| | **A · Railway** | **B · GitHub Actions** |
|---|---|---|
| How it runs | Windows inside QEMU in a Linux container | Real Windows runner (`windows-latest` / `windows-2025` / `windows-2022`) |
| Speed | **Slow** (no KVM on Railway → software emulation) | Fast (real VM) |
| Lasts | Until you stop it (data on a Volume) | Max **6 h** per run, everything erased after |
| Access | Public **TCP Proxy** `:3389` **or** private **Tailscale** | **Tailscale** (auth key in Secrets/Variables) |
| Secrets live in | Railway **Variables** | GitHub **Secrets and variables → Actions** |

Both modes include the **Storage Booster** and the Kazama **wallpaper**.

## ⚠️ Honest limits

- **Railway is slow.** Railway does not expose `/dev/kvm`, so the first install can take **hours** and the desktop feels sluggish. It also needs a **Volume at `/storage`** (roughly 20–30 GB) and **≥ 4 GB RAM** — check your plan's limits.
- **GitHub Actions is not meant for this.** GitHub's terms limit Actions to building/testing/deploying your project; using it as a remote desktop can get the repository or account restricted. Use at your own risk, preferably on a private repo you can afford to lose.
- **Not a VPS** in either mode: no persistent server, no custom kernel.
- Windows licensing and activation are your responsibility.

---

## 🅰️ Mode A — Railway

1. **Fork** this repository and connect it to a new Railway project.
2. **Variables:** set `RDP_PASSWORD` (required). Optional: `WINDOWS_VERSION`, `TAILSCALE_AUTHKEY`.
3. **Settings → Volumes:** add a Volume mounted at **`/storage`**.
4. **Pick one way to connect:**
   - **Tailscale (recommended, private):** set `TAILSCALE_AUTHKEY`. No public port is opened.
   - **Public TCP Proxy:** **Settings → Networking → TCP Proxy**, port **`3389`**.

   <img src="assets/tcp-port.png" alt="Add TCP Proxy" width="420"/>

   (Use `3389`, not the `22` shown in the screenshot.)
5. Set `RAILWAY_DEPLOYMENT_DRAINING_SECONDS=60` so Windows can shut down cleanly on redeploy.
6. **Deploy** and follow the **Deploy Logs** until Windows has installed and booted.

### Railway variables

| Variable | Required | Default | Description |
|----------|:--------:|---------|-------------|
| `RDP_PASSWORD` | ✅ | — | Windows user password. 8+ chars, 3 of lower/UPPER/digits/symbols, **no spaces or `< > & " '`**, must not contain the username. |
| `WINDOWS_VERSION` | — | `windows-latest` | `windows-latest` (Server 2025), `windows-2025`, `windows-2022`. |
| `RDP_USERNAME` | — | `kazama` | Administrator account created at install. |
| `TAILSCALE_AUTHKEY` | — | — | Enables private access over Tailscale. Use an **ephemeral, reusable** key. |
| `TAILSCALE_HOSTNAME` | — | `kazama-windows` | Machine name in your tailnet. |
| `BOOSTER_MODE` | — | `safe` | `off`, `safe`, `deep` — see [Storage Booster](#-storage-booster). |
| `BOOSTER_SCHEDULE` | — | `weekly` | `off`, `daily`, `weekly` (03:00, inside Windows). |
| `KAZAMA_WALLPAPER` | — | `true` | Apply the Kazama wallpaper on each user's first logon. |
| `RAM_SIZE` / `CPU_CORES` / `DISK_SIZE` | — | `4G` / `2` / `40G` | VM resources (must fit your plan / Volume). |
| `APP_LANG` | — | `en` | Log language: `en` or `id`. |

> ℹ️ `RDP_PASSWORD`, `RDP_USERNAME`, `WINDOWS_VERSION` and the booster/wallpaper settings are applied **only at the first install**. Change the password later inside Windows; to change the Windows version, wipe the Volume.

---

## 🅱️ Mode B — GitHub Actions (Tailscale)

1. Create a **private** repository from this one (or fork it).
2. Create a Tailscale **auth key** at <https://login.tailscale.com/admin/settings/keys> — tick **Reusable** and **Ephemeral**.
3. In the repo: **Settings → Secrets and variables → Actions**
   - **Secrets:** `RDP_PASSWORD`, `TAILSCALE_AUTHKEY`
   - (Variables with the same names are accepted as a fallback, but they are **not masked** — prefer Secrets.)
4. **Actions → "Kazama Windows RDP (Tailscale)" → Run workflow** and choose **windows-latest**, **windows-2025** or **windows-2022**, plus the booster level.
5. When the run reaches *Keep session alive*, open the **job summary** for the address, then connect.

Inputs: Windows version · `boost` (off/safe/deep) · `duration` (max 345 min) · `idle_timeout` (stops when nobody is connected) · `username` · Tailscale name · extra Chocolatey `packages` · `save_files` (uploads Desktop + Documents when it ends) · `language`.

---

## 🔌 Connect with Windows App

1. If you use Tailscale, make sure it is running on your device and signed in to the same tailnet.
2. **Windows App → + → PC.**
3. **PC name:** the Tailscale IP / machine name, **or** (Railway TCP Proxy) `<proxy-domain>:<proxy-port>`.
4. **User account → Add user account:** username = `RDP_USERNAME` (default `kazama`), password = `RDP_PASSWORD`.
5. Save, connect, accept the certificate prompt.

---

## 🧹 Storage Booster

Frees disk space on `C:` by deleting files Windows can rebuild or never needs, then shows
**free space before → after** (e.g. `30 GB → 50 GB`). How much you gain depends on the machine.

| Mode | What it removes |
|------|-----------------|
| **safe** | Temp files, crash dumps, Windows Update download cache, Delivery Optimization cache, error reports, CBS logs, Edge/Chrome caches, npm/pip caches, Recycle Bin, + disk TRIM |
| **deep** | everything in *safe* **plus** Windows component store clean-up (`DISM /ResetBase`), hibernation file, shadow copies, event logs, `Windows.old`, and — on GitHub runners — bulky pre-installed SDKs (Android, ghcup, Miniconda, MySQL, PostgreSQL, MongoDB) |

- **Desktop shortcut** *Kazama Storage Booster* — run it any time (it asks for admin rights).
- **Automatic run** — Railway mode: scheduled task (`BOOSTER_SCHEDULE`); Actions mode: runs before you connect.
- Settings and log: `C:\Kazama\kazama.conf`, `C:\Kazama\booster.log`.
- `deep` is for disposable desktops: it makes installed Windows updates non-removable.

---

## 🗂️ Project structure

```text
.
├── Dockerfile                       # Mode A: dockurr/windows + Kazama wrapper + Tailscale
├── compose.yml                      # run locally (Linux host with KVM)
├── railway.json / railway-template.json
├── rootfs/usr/local/
│   ├── bin/kazama-entrypoint        # validation, version mapping, Tailscale, OEM config
│   └── lib/kazama/common.sh         # i18n (en/id) + logging
├── windows/                         # runs INSIDE Windows (both modes)
│   ├── install.bat                  # Railway: executed by dockur at the end of install
│   ├── kazama-setup.ps1             # wallpaper task, booster shortcut + schedule
│   ├── kazama-booster.ps1           # Storage Booster
│   └── kazama-wallpaper.ps1         # per-user wallpaper
├── scripts/                         # Mode B: GitHub Actions runner scripts
├── assets/                          # wallpaper + screenshot
└── .github/workflows/
    ├── rdp.yml                      # Mode B workflow
    └── ci.yml                       # ShellCheck + PowerShell syntax + Docker build
```

## 🔒 Security

- Public RDP is probed constantly — use a **long, unique `RDP_PASSWORD`** and prefer **Tailscale** (NLA stays enabled either way).
- The web viewer (port 8006) has no password. **Do not create a public Railway domain for it.** Over Tailscale it is reachable privately at `<tailscale-ip>:8006`.
- Keep keys and passwords in Railway Variables / GitHub **Secrets**, never in the repo.

## 🩺 Troubleshooting

| Problem | Fix |
|---------|-----|
| Container exits immediately | The log says why — missing/weak `RDP_PASSWORD`, or unsupported `WINDOWS_VERSION`. |
| Windows reinstalls every deploy | No Volume at `/storage`. |
| Tailscale does not connect (Railway) | See the deploy logs; check the auth key. Tailscale must run on your device too. |
| Wallpaper not shown | Applied on each user's first logon; the Windows App client must have *Desktop background* enabled. |
| `RDP_PASSWORD is missing` (Actions) | Add it under **Secrets and variables → Actions**. |

## 🛠️ Run locally

On a Linux host with KVM this is **fast**:

```bash
RDP_PASSWORD='Str0ng#Pass9' docker compose up --build
# web viewer: http://localhost:8006   ·   RDP: localhost:3389
```

## 📄 License

MIT — see [LICENSE](LICENSE). Mode A builds on [dockur/windows](https://github.com/dockur/windows) (MIT).

---

<p align="center">
  © Kazama Tech · Developed by <a href="https://github.com/kazamaofficial-git"><b>@kazamaofficial-git</b></a> ·
  <a href="https://github.com/kazamaofficial-git/kazama-windows">Repository</a>
</p>
