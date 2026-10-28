# Aktivasi akun peserta Olympiad

1. Gunakan proyek Supabase khusus Olympiad.
2. Jalankan supabase/migrations/20261028_participant_profiles.sql di SQL Editor.
3. Vercel Preview dan Production: isi OLYMPIAD_SUPABASE_URL dan OLYMPIAD_SUPABASE_ANON_KEY (publishable atau legacy anon, BUKAN secret/service_role).
4. Supabase Authentication Providers: aktifkan Email, konfirmasi email, dan Google.
5. Google Cloud OAuth Web Client redirect URI: https://<project-ref>.supabase.co/auth/v1/callback. Simpan Client ID/Secret di provider Google Supabase, bukan kode.
6. Supabase URL Configuration: Site URL domain produksi. Allowlist EXACT https://<domain>/auth-callback.html dan https://<domain>/auth-callback.html?flow=recovery untuk produksi serta domain preview. Seluruh alur harus memakai origin/browser yang sama.
7. Redeploy setelah environment variables diubah.
8. Uji email signup, konfirmasi, login/logout, Google, profil, lupa sandi, dan isolasi dua akun.

## Catatan
Supabase JS v2 dari CDN, PKCE, getUser, storage key khusus Olympiad. Password tidak disimpan aplikasi. Metadata tidak digunakan sebagai hak admin. Profil RLS hanya pemilik akun. Callback tidak menerima tujuan redirect arbitrer. /api/auth-config hanya mengeluarkan URL dan public key.
Tanpa konfigurasi env, kontrol login dinonaktifkan. Migrasi dan pengaturan provider tidak dijalankan otomatis. Halaman peserta awal hanya profil dan logout, belum panel ujian.

## Referensi
https://supabase.com/docs/reference/javascript/auth-signinwithoauth
https://supabase.com/docs/guides/auth/sessions/pkce-flow
https://supabase.com/docs/guides/auth/social-login/auth-google