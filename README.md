# Jenius Olympiad by Jenius Edu

Website publik kompetisi akademik SD/SMP/SMA, desain responsif, Blog, Panduan, Pengumuman, dan FAQ.

## Akun peserta
Integrasi Supabase tersedia untuk signup email + konfirmasi, login email, Google OAuth PKCE, lupa/reset sandi, profil peserta dan logout. Aktivasi memerlukan environment Vercel, migrasi SQL, redirect allowlist, dan provider Google. Lihat [panduan aktivasi](docs/participant-auth.md).

Database dan provider tidak dikonfigurasi otomatis. Halaman akun tetap diblokir jika konfigurasi belum tersedia. Jadwal, kompetisi aktif, pembayaran, dan sistem ujian belum diluncurkan.

## Struktur
- js/auth.js, css/auth.css: UI login/daftar
- js/participant-client.js: koneksi Supabase publik
- js/participant-account.js: callback, profil, pemulihan sandi
- api/auth-config.js: environment publik tervalidasi
- supabase/migrations: tabel profil dan RLS

Preview harus diuji sebelum merge ke main. Pengelolaan kompetisi akan dikembangkan melalui panel pengelola.
