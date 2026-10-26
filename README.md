# JeniusOlympiad by Jenius Edu

Fondasi website publik untuk **JeniusOlympiad**, bagian dari ekosistem Jenius Education.

## Status

Tahap awal: halaman publik responsif dan navigasi dasar. **Belum ada autentikasi, CBT, pembayaran, atau database aktif.** Seluruh data pada halaman adalah placeholder; tidak menampilkan angka peserta atau jadwal fiktif.

## Struktur

- `index.html` — halaman publik awal dan bagian menu.
- `css/style.css` — desain responsif.
- `js/app.js` — navigasi mobile dan tahun footer.
- `vercel.json` — konfigurasi deployment statis.

## Arsitektur lanjutan

Website ini melayani peserta/publik. Semua administrasi akan dikembangkan terpusat di **Panel Pengelola** pada repository `Alfin354313/panel-baru`. Integrasi menggunakan API backend aman, tanpa mengekspos kunci layanan ke browser.

## Pengembangan

Branch `feature/initial-site-structure` untuk review/preview sebelum merge ke `main`.
