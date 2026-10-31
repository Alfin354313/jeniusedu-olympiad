# Simulasi, bantuan, pengingat, laporan, dan sertifikat massal

## Aktivasi

Kode tetap berada di branch preview Olympiad dan Panel; belum digabung ke main. Tidak ada SQL produksi atau penerbitan sertifikat nyata yang dilakukan oleh agen.

Setelah lifecycle dan bank/recovery yang sebelumnya sudah dijalankan, gunakan **satu** jalur:

- Jika kartu/pengumuman/final sudah diaktifkan: jalankan `20261103_readiness_reports_bulk.sql` (Panel: `supabase/olympiad_readiness_reports_bulk.sql`).
- Jika belum atau ingin menjalankan satu skrip lengkap: jalankan `supabase/olympiad_program_and_readiness.sql` di repo Panel. Bundel ini menggabungkan tahap kartu/final dengan tahap ini; boleh diulang tanpa mengganti nomor peserta atau sertifikat lama.

Jalankan pada proyek Supabase yang dikonfigurasi Olympiad, saat ini sama dengan Panel. Jangan menjalankan definisi lifecycle/bank lama setelah upgrade karena dapat mengganti RPC terbaru. Jalur incremental baru tidak menilai ulang hasil lama dan tidak mengubah rekening.

## Peserta

**Simulasi Gratis** → Buka Simulasi: lima soal contoh matematika sesuai SD/SMP/SMA, timer latihan 10 menit, navigasi, kosongkan jawaban, simpan lokal, lanjut setelah reload, kumpulkan atau otomatis selesai saat waktu habis, nilai dan pembahasan. Latihan dapat diulang. Ini contoh antarmuka, bukan bank kompetisi atau prediksi materi lomba. Timer latihan memakai perangkat, sementara ujian resmi tetap memakai server. Hanya identitas internal akun, jenjang, pilihan jawaban dan waktu latihan disimpan di browser; tidak ada pengiriman nilai simulasi ke laporan, peringkat atau sertifikat. Logout membersihkan latihan milik akun tersebut. Penyimpanan yang diblokir ditandai dan latihan tetap dapat berjalan selama halaman terbuka.

**Pusat Bantuan**: panduan yang bisa dicari untuk pembayaran, koneksi, jadwal, final, kartu dan hasil. Tombol WhatsApp/email hanya muncul jika kontak resmi diatur pengelola pada **Bantuan & Kontak**. Nomor WhatsApp memakai kode negara tanpa +/spasi; nomor/email tidak diisi dengan data contoh secara otomatis. Tombol hanya membuka aplikasi kontak; tidak ada pesan yang dikirim oleh sistem.

**Pengingat Akun**: kartu pada dashboard dan ringkasan lonceng, berasal dari RPC milik akun. Pembayaran yang belum selesai, bukti menunggu verifikasi, ujian dalam 24 jam atau sedang dibuka, kelulusan final yang aktif dan hasil yang sudah diumumkan. Jadwal ditentukan server. Pemutakhiran mengikuti polling akun 30 detik ketika halaman terlihat; bukan email, push, SMS, atau pengingat di luar situs. Hasil yang sudah dirilis tetap tampil sebagai informasi; belum ada status sudah dibaca.

## Pengelola

**Laporan Kompetisi**: pilih kompetisi, lihat status pendaftaran, pemasukan terverifikasi (approved, nominal > 0), nominal belum terverifikasi, keikutsertaan ujian, distribusi nilai, rata-rata/minimum/maksimum, penetapan lolos dan sertifikat aktif. Nilai hanya dari peserta aktif yang sudah mengumpulkan. Data kosong ditampilkan tanpa menciptakan nilai rata-rata nol. Final gratis tidak dihitung sebagai pembayaran. Laporan membaca keadaan saat dimuat, tidak memfinalisasi ujian atau mengubah data. Gunakan Muat Ulang untuk data terbaru. CSV merangkum laporan dengan pelindung formula spreadsheet yang sudah ada. Penetapan lolos dihitung per akses final (jika satu penyisihan mempunyai beberapa final, satu peserta dapat terhitung lebih dari sekali).

**Sertifikat Massal**: pilih kompetisi dengan hasil yang sudah diumumkan dan jadwal berakhir; isi penghargaan; muat pratinjau; pilih penerima; periksa nama dan isi penghargaan; centang pemeriksaan; konfirmasi penerbitan. Maksimal 500 penerima per batch. Pratinjau menampilkan calon yang belum bersertifikat terlebih dahulu. Muat ulang pratinjau setelah satu batch selesai untuk penerima berikutnya. Penghargaan tetap keputusan pengelola, bukan otomatis berdasarkan peringkat.

Server memeriksa kembali status aktif, pengumpulan ujian, hasil diumumkan, dan sidik data pratinjau. Perubahan nama/nilai/judul/penghargaan membatalkan pratinjau lama. Setiap batch bersifat atomik dan memiliki ID retry: jika respons koneksi hilang, ulangi tombol dengan pilihan yang sama; sertifikat tidak digandakan. Sertifikat yang sudah ada, termasuk yang dicabut, tidak ditimpa atau diaktifkan ulang. Terbitkan manual/revoke tetap tersedia pada Hasil & Sertifikat. Batch dicatat dalam tabel privat dan log audit. Fitur ini membuat sertifikat pada akun dan halaman verifikasi yang sudah ada, bukan mengirim massal lewat email atau ZIP PDF.

## Pengujian

PGlite: migrasi berulang; batas hak akses; validasi kontak; isolasi pengingat; ketepatan agregat (termasuk data kosong/final gratis); pratinjau, penolakan perubahan data, transaksi batch atomik, retry, pencegahan duplikasi dan perlindungan sertifikat dicabut. jsdom: simulasi/timer/penyimpanan/hasil/logout, menu bantuan/pencarian, pengingat, laporan CSV, pemilihan dan konfirmasi sertifikat, retry respons ambigu, pengaturan kontak. Regresi ujian nyata, recovery, bank soal, dan tahapan final tetap diperiksa.

Browser cloud tidak merespons saat dicoba. Pemeriksaan visual langsung, PDF fisik, transfer nyata dan uji beban belum dilakukan. Setelah aktivasi SQL, lakukan uji dengan akun pengelola/peserta di preview sebelum peluncuran.
