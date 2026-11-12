# 🦅 Kazama Windows di Pterodactyl

[🇬🇧 English](README.md) · [🇮🇩 Bahasa Indonesia](README.id.md) · [← Kembali ke README utama](../README.id.md)

Jalankan **Kazama Windows RDP** sebagai server di panel [Pterodactyl](https://pterodactyl.io) Anda sendiri dengan egg siap pakai
[`egg-kazama-windows.json`](egg-kazama-windows.json). Anda terhubung dengan **Windows App** lewat RDP — ini desktop RDP, **bukan VPS**.

> ⚠️ **Baca bagian berikutnya dulu.** Node Pterodactyl standar tidak bisa menjalankan image ini. Panduan di bawah menjelaskan persis apa yang harus diizinkan node, dan apa harganya bagi keamanan. Saya **belum** bisa mengujinya di node Wings sungguhan — anggap ini eksperimental.

---

## 1. Kenapa node Wings standar tidak cukup

Wings memulai setiap container server dengan batasan yang tidak cocok untuk Windows-di-QEMU:

| Default Wings | Yang dibutuhkan Kazama Windows |
|---|---|
| Berjalan sebagai user tanpa hak istimewa (UID 988) | **root** (QEMU, helper jaringan) |
| Root filesystem **read-only** | `/run`, `/var`, `/oem` … yang bisa ditulis |
| Capability dibuang, `no-new-privileges` | `NET_ADMIN` opsional (cadangannya jaringan user-mode) |
| Tanpa `/dev/kvm` | `/dev/kvm` opsional, tetapi tanpanya Windows berjalan dengan **emulasi software** (sangat lambat) |
| Hanya `/home/container` yang persisten | **`/storage`** yang persisten (disk Windows, ~20–30 GB) |

Jadi node membutuhkan tiga hal, plus satu peningkatan opsional:

1. 🔓 container server berjalan sebagai **root**
2. ✍️ root filesystem **bisa ditulis**
3. 💾 **Mount** persisten di `/storage`
4. ⚡ *(opsional, percepatan besar)* container **privileged** di host yang punya `/dev/kvm` → akselerasi KVM sungguhan

**Pakai node khusus saja.** Melonggarkan pengaturan ini menghilangkan isolasi yang melindungi server lain dan host dari container yang diretas. Jangan lakukan di node yang dipakai bersama orang yang tidak sepenuhnya Anda percaya.

---

## 2. Checklist

- [ ] Panel Pterodactyl + node Wings yang Anda kelola (khusus untuk ini)
- [ ] Node dengan **RAM kosong ≥ 6 GB** dan **disk ≥ 45 GB**
- [ ] Opsional: host dengan KVM (`ls /dev/kvm` berhasil di node)
- [ ] Wings dikonfigurasi seperti di langkah 4 (root + rootfs writable + allowed mount)
- [ ] Image sudah dipublikasikan ke GHCR (langkah 1)
- [ ] Port **3389** (RDP) dan opsional **8006** (web viewer — jaga tetap privat) kosong di IP node

---

## 3. Langkah demi langkah

### Langkah 1 — Publikasikan image

Egg mengambil `ghcr.io/kazamaofficial-git/kazama-windows:latest`.

1. Di repository GitHub buka **Actions → Publish image → Run workflow** (atau push tag seperti `v1.0.0`).
2. Setelah selesai, buka **Packages → kazama-windows → Package settings** di repository dan atur **Visibility: Public** agar Wings bisa menariknya tanpa login.

### Langkah 2 — Impor egg

1. Panel → **Admin → Nests** → pilih (atau buat) nest, mis. *Kazama*.
2. **Import Egg** → unggah [`egg-kazama-windows.json`](egg-kazama-windows.json) → pilih nest → **Import**.

### Langkah 3 — Buat Mount persisten

Windows harus menyimpan disknya antar restart.

1. Di node, buat folder dan berikan ke user Wings:

   ```bash
   sudo mkdir -p /var/lib/kazama-windows
   sudo chown -R pterodactyl:pterodactyl /var/lib/kazama-windows   # pakai root:root jika container Anda berjalan sebagai root
   ```
2. Edit `/etc/pterodactyl/config.yml` di node dan izinkan path-nya:

   ```yaml
   allowed_mounts:
     - /var/lib/kazama-windows
   ```
3. Restart Wings: `sudo systemctl restart wings`.
4. Panel → **Admin → Mounts → Create New**:
   - **Name:** `kazama-windows-storage`
   - **Source:** `/var/lib/kazama-windows`
   - **Target:** `/storage`
   - **Read only:** mati
   - Setelah disimpan, buka mount itu dan pasang ke egg **Kazama Windows RDP** dan **node** Anda.

> Satu Mount punya satu folder sumber tetap. Untuk beberapa server Windows, buat satu mount per server dan pasang ke server masing-masing, bukan ke seluruh egg.

### Langkah 4 — Izinkan root + rootfs writable di node (khusus node dedicated)

Wings standar membuat container dengan user non-root, root filesystem read-only, dan `no-new-privileges`. Panduan komunitas melonggarkannya dengan membangun Wings dari source dan mengubah konfigurasi host container di `environment/docker/container.go` (nomor baris berbeda per versi Wings):

1. Jalankan container sebagai root (atur user container ke `0:0`).
2. Hapus baris `SecurityOpt: []string{"no-new-privileges"}`.
3. Ubah `ReadonlyRootfs: true` menjadi `ReadonlyRootfs: false`.
4. *(Opsional, untuk KVM)* tambahkan `Privileged: true`. Container privileged melihat `/dev/kvm` host dan mendapat `NET_ADMIN`, sehingga Windows berjalan dengan **akselerasi KVM**, bukan emulasi.

Lalu `go build`, ganti binary Wings, dan restart. Lakukan hanya jika Anda paham dampak keamanannya (lihat bagian 1). Saya tidak bisa memverifikasi perubahan ini terhadap versi Wings Anda.

### Langkah 5 — Allocation (port)

Pterodactyl memublikasikan allocation sebagai **nomor port yang sama** di host dan di dalam container, sedangkan Windows mendengarkan di **3389** di dalam container. Jadi:

- Jadikan **3389** sebagai **primary allocation** server (buat allocation di **Admin → Nodes → node Anda → Allocation**).
- Opsional: tambahkan **8006** sebagai allocation tambahan untuk web viewer — hanya boleh dijangkau Anda (firewall), karena tanpa password.
- Utamakan **Tailscale** (isi `TAILSCALE_AUTHKEY`): dengan begitu 3389 tidak perlu dibuka sama sekali.

Jika IP node sudah memakai port 3389, beri node IP/alias lain dan buat allocation 3389 di sana.

### Langkah 6 — Buat server

**Admin → Servers → Create New:**

| Field | Nilai |
|---|---|
| Egg | **Kazama Windows RDP** |
| Docker image | `Kazama Windows (latest)` |
| Memory | **minimal `RAM_SIZE` + 1 GB** (mis. `5120` MB untuk default 4G) |
| CPU | mis. `200`% untuk 2 core |
| Disk | **≥ 45000 MB** |
| Swap | `0` |
| Primary allocation | yang berport **3389** |
| `RDP_PASSWORD` | password kuat Anda (wajib) |
| Variabel lain | lihat tabel di bawah |

### Langkah 7 — Start dan tunggu

Start server dan pantau console. Boot pertama **mengunduh dan menginstal Windows** — tanpa KVM bisa **berjam-jam**. Baris merah seperti *"KVM acceleration is not available"* atau *"failed to create bridge … NET_ADMIN"* adalah **peringatan, bukan crash**: instalasi lanjut dengan emulasi software dan jaringan user-mode.

### Langkah 8 — Hubungkan

**Windows App → + → PC:** PC name `<ip-node>:3389` (atau IP/nama Tailscale Anda), user account `RDP_USERNAME` / `RDP_PASSWORD`, lalu setujui peringatan sertifikat.

---

## 4. Variabel

| Variabel | Default | Keterangan |
|---|---|---|
| `RDP_PASSWORD` | — (wajib) | Password user Windows. Min 8 karakter, 3 dari huruf kecil/BESAR/angka/simbol, **tanpa spasi atau `< > & " '`**, tidak boleh memuat username. |
| `RDP_USERNAME` | `kazama` | Akun administrator yang dibuat saat instalasi. |
| `WINDOWS_VERSION` | `windows-latest` | `windows-latest` (Server 2025), `windows-2025`, `windows-2022`. |
| `RAM_SIZE` | `4G` | RAM untuk Windows (harus muat di batas memori server). |
| `CPU_CORES` | `2` | Jumlah vCPU untuk Windows. |
| `DISK_SIZE` | `40G` | Ukuran disk virtual (harus muat di mount `/storage`). |
| `APP_LANG` | `en` | Bahasa log: `en` atau `id`. |
| `TAILSCALE_AUTHKEY` | — | Key reusable + ephemeral → RDP privat lewat Tailscale. |
| `TAILSCALE_HOSTNAME` | `kazama-windows` | Nama mesin di tailnet Anda. |
| `BOOSTER_MODE` | `safe` | Storage Booster di Windows: `off`, `safe`, `deep`, `max` (lihat README utama). |
| `BOOSTER_SCHEDULE` | `weekly` | `off`, `daily`, `weekly` (03:00). |
| `BOOSTER_KEEP` | `chrome` | Id katalog yang tidak boleh dihapus `max`, mis. `chrome,visualstudio`. |
| `KAZAMA_WALLPAPER` | `true` | Terapkan wallpaper Kazama saat logon pertama. |
| `KAZAMA_TUNE` | `light` | Tuning performa untuk emulasi: `off`, `light`, `max`. |

`RDP_PASSWORD`, `RDP_USERNAME`, `WINDOWS_VERSION`, dan pengaturan booster/tune/wallpaper hanya berlaku saat **instalasi pertama**. Untuk mengganti password nanti lakukan di dalam Windows; untuk mengganti versi Windows, kosongkan folder `/storage` lalu instal ulang.

---

## 5. Menghentikan server

Egg menghentikan server dengan `^C` (SIGINT); image lalu meminta Windows shutdown. Shutdown Windows yang bersih bisa memakan sekitar 2 menit. Jika versi Wings Anda mematikan container lebih cepat, shutdown Windows dari dalam sesi RDP (Start → Power → Shut down) **sebelum** menghentikan server, jika tidak disk bisa tertinggal dalam kondisi tidak bersih.

---

## 6. Pemecahan masalah

| Masalah | Kemungkinan penyebab / solusi |
|---|---|
| Container langsung berhenti dengan error permission atau "read-only file system" | Node masih menjalankan container sebagai non-root / dengan root filesystem read-only — langkah 4. |
| Image tidak bisa di-pull | Package GHCR belum public (langkah 1) atau workflow Publish belum dijalankan. |
| Windows diinstal ulang tiap restart | Mount `/storage` belum ada atau belum dipasang ke egg/server (langkah 3). |
| Console menampilkan `RDP_PASSWORD is required` / error password | Perbaiki variabelnya; aturan ada di bagian 4. |
| Tidak bisa terhubung via RDP | Tunggu sampai Windows selesai terinstal; pastikan allocation 3389 adalah primary dan firewall mengizinkannya — atau pakai Tailscale. |
| Sangat lambat | Tanpa KVM. Pakai node dengan `/dev/kvm` + container privileged (langkah 4), atau isi `KAZAMA_TUNE=light`/`max`. |
| Mengubah `RDP_PASSWORD` tidak berpengaruh | Hanya berlaku saat instalasi pertama — ubah di dalam Windows. |

---

## 7. Keamanan

- Siapa pun yang bisa menjangkau RDP bisa mencoba login: pakai password panjang dan unik, dan utamakan **Tailscale**.
- **Jangan** membuka port 8006 ke publik; web viewer tidak punya password.
- Melonggarkan Wings (root, rootfs writable, privileged) melemahkan isolasi — hanya untuk node dedicated.

---

<p align="center">
  © Kazama Tech · Dikembangkan oleh <a href="https://github.com/kazamaofficial-git"><b>@kazamaofficial-git</b></a>
</p>
