# Kartu peserta, pengumuman, dan tahapan final

Aktifkan **20261102_cards_announcements_stages.sql** setelah profil, lifecycle, dan bank_recovery_monitor yang sudah dijalankan. Salinan identik ada di Panel: `supabase/olympiad_cards_announcements_stages.sql`. Jalankan satu salinan saja pada proyek Supabase Olympiad yang sama dengan konfigurasi akun. Skrip boleh diulang: nomor lama dipertahankan. Jangan jalankan ulang definisi lifecycle atau upgrade lama setelah skrip ini karena dapat mengganti RPC terbaru. Tidak ada SQL produksi yang dijalankan oleh agen.

## Kartu

Menu Kartu Peserta menampilkan pendaftaran aktif; halaman kartu memerlukan login pemilik atau pengelola dan status approved. Nomor JO-tahun-urutan dibuat server per pendaftaran (nomor berbeda untuk final). Nomor bukan kode autentikasi. Tidak ada pencarian publik atas identitas peserta. Cetak/Save PDF memakai dialog cetak browser; tidak ada tanda tangan atau klaim penghargaan.

## Pengumuman

Panel → Olympiad → Pengumuman: judul, isi teks biasa, penerima Publik/Peserta aktif, kompetisi atau semua, jadwal mulai/berakhir, sematkan, dan terbitkan. Waktu input mengikuti perangkat; data tersimpan sebagai timestamptz. Pengumuman publik dibaca melalui RPC khusus publik, termasuk ketika browser sudah login. Pesan global peserta memerlukan profil; pesan kompetisi memerlukan pendaftaran approved. Draf, pesan kedaluwarsa dan yang belum waktunya tidak dikirim ke peserta. Ini pengumuman dalam situs, bukan email/push; tidak ada status sudah dibaca.

## Penyisihan dan final

Kompetisi lama bisa menjadi sumber penyisihan tanpa mengubah pengerjaan yang sudah terkunci. Tahapan & Kelulusan → pilih penyisihan → Buat Final. Final adalah kompetisi tersendiri dengan soal, jadwal dan hasil sendiri; jenjang harus sama, mulai setelah penyisihan berakhir, biaya selalu nol. Tambahkan soal saat draf dan terbitkan melalui Kompetisi. Final ditampilkan sebagai khusus peserta lolos dan tidak menerima pendaftaran mandiri/pembelian ulang.

Umumkan hasil penyisihan melalui Hasil & Sertifikat. Pada Tahapan & Kelulusan, pilih final, pilih kandidat, isi dasar keputusan dan Tetapkan Lolos. Pilih N teratas menyertakan semua peserta yang nilainya sama pada batas; pengelola tetap mengonfirmasi jumlah aktual. Tidak ada medali/kelulusan otomatis. Server hanya menerima peserta aktif yang sudah mengumpulkan penyisihan. Penetapan ulang mempertahankan registrasi/nomor final dan tidak menagih ulang. Cabut Kelulusan adalah aksi terpisah dengan alasan; hanya sebelum final mulai dan sebelum peserta memulai pengerjaan. Final yang dicabut tidak memberi akses ujian/kartu. Keputusan masuk log audit, alasan terbaru disimpan pada data kualifikasi privat.

Setelah final dimulai, monitoring, penyimpanan jawaban, hasil dan sertifikat memakai alur ujian yang sama. Tahapan hanya satu penyisihan → final; final tidak dapat menjadi induk putaran lain.

## Validasi dan batas

PGlite: migrasi diulang, nomor stabil/unik, penolakan kartu akun lain, pemisahan penerima/waktu pengumuman, penolakan pembelian final, penetapan/cabut/ulang, final gratis dan akses ujian. jsdom: pilihan batas seri, simpan pengumuman, escaping teks, menu kartu dan tombol cetak; regresi ujian dan pemulihan jawaban tetap berjalan. Pengujian browser langsung dan cetakan fisik belum dilakukan karena transport browser tidak tersedia. Uji coba akun pengelola/peserta pada preview setelah aktivasi SQL tetap diperlukan. Perubahan belum digabung ke main.
