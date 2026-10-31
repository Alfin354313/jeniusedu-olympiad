// Public example exercises only. These are never copied from a competition bank.
export const practiceQuestions={
 SD:[
 {prompt:'125 + 75 = …',options:['175','190','200','225'],answer:2,explanation:'125 + 75 = 200.'},
 {prompt:'Persegi panjang memiliki panjang 8 cm dan lebar 5 cm. Kelilingnya adalah …',options:['13 cm','26 cm','40 cm','80 cm'],answer:1,explanation:'Keliling = 2 × (8 + 5) = 26 cm.'},
 {prompt:'1/2 + 1/4 = …',options:['2/6','1/6','1/2','3/4'],answer:3,explanation:'Samakan penyebut: 1/2 = 2/4, sehingga 2/4 + 1/4 = 3/4.'},
 {prompt:'Lanjutkan pola 3, 6, 12, 24, …',options:['48','36','30','27'],answer:0,explanation:'Setiap bilangan dikalikan 2. Bilangan selanjutnya adalah 24 × 2 = 48.'},
 {prompt:'Sebuah segitiga memiliki berapa sisi?',options:['2','3','4','5'],answer:1,explanation:'Segitiga memiliki tiga sisi.'}
 ],
 SMP:[
 {prompt:'Nilai −4 + 3 × 5 adalah …',options:['−5','35','11','19'],answer:2,explanation:'Dahulukan perkalian: −4 + 15 = 11.'},
 {prompt:'Jika 2x + 7 = 19, nilai x adalah …',options:['13','6','12','3'],answer:1,explanation:'2x = 19 − 7 = 12, maka x = 6.'},
 {prompt:'Perbandingan banyak buku Ani dan Budi adalah 2 : 3. Jika jumlahnya 40 buku, banyak buku Ani adalah …',options:['8','24','20','16'],answer:3,explanation:'Bagian Ani = 2/(2 + 3) × 40 = 16 buku.'},
 {prompt:'Rata-rata dari 6, 7, 8, dan 9 adalah …',options:['7,5','7','8','8,5'],answer:0,explanation:'Jumlah data = 30. Rata-rata = 30 ÷ 4 = 7,5.'},
 {prompt:'Segitiga dengan alas 12 cm dan tinggi 7 cm memiliki luas …',options:['84 cm²','42 cm²','19 cm²','38 cm²'],answer:1,explanation:'Luas = 1/2 × alas × tinggi = 1/2 × 12 × 7 = 42 cm².'}
 ],
 SMA:[
 {prompt:'Nilai 3² × 3³ adalah …',options:['81','729','243','36'],answer:2,explanation:'Basis sama: 3² × 3³ = 3⁵ = 243.'},
 {prompt:'Akar-akar persamaan x² − 5x + 6 = 0 adalah …',options:['−2 dan −3','2 dan 3','1 dan 6','−1 dan −6'],answer:1,explanation:'x² − 5x + 6 = (x − 2)(x − 3), maka x = 2 atau x = 3.'},
 {prompt:'Sebuah dadu seimbang dilempar sekali. Peluang muncul bilangan genap adalah …',options:['1/6','1/3','2/3','1/2'],answer:3,explanation:'Bilangan genap adalah 2, 4, dan 6: ada 3 dari 6 kemungkinan. Peluang = 3/6 = 1/2.'},
 {prompt:'Suku ke-10 barisan aritmetika 5, 9, 13, … adalah …',options:['41','37','45','50'],answer:0,explanation:'Suku ke-n = 5 + (n − 1) × 4. Untuk n = 10, hasilnya 5 + 36 = 41.'},
 {prompt:'Jika f(x) = 2x + 1, maka f(4) = …',options:['8','9','6','12'],answer:1,explanation:'Substitusikan x = 4: f(4) = 2 × 4 + 1 = 9.'}
 ]};
export const practiceDuration=600000;
export function parsePractice(raw,user,now=Date.now()){
 try{if(!raw||raw.length>5000)return null;const s=JSON.parse(raw);if(!Object.hasOwn(practiceQuestions,s.level))return null;const qs=practiceQuestions[s.level];if(s.version!==1||s.user!==user||!qs||!Number.isFinite(s.startedAt)||s.startedAt>now+60000||now-s.startedAt>86400000||s.deadline!==s.startedAt+practiceDuration||!Array.isArray(s.answers)||s.answers.length!==qs.length||!s.answers.every((a,i)=>a===null||Number.isInteger(a)&&a>=0&&a<qs[i].options.length)||!Number.isInteger(s.index)||s.index<0||s.index>=qs.length||!(s.submittedAt===null||Number.isFinite(s.submittedAt)&&s.submittedAt>=s.startedAt&&s.submittedAt<=now+60000))return null;return s;}catch{return null;}
}
export function practiceScore(s){const qs=practiceQuestions[s.level],correct=qs.filter((q,i)=>s.answers[i]===q.answer).length,blank=s.answers.filter(x=>x===null).length;return {correct,blank,wrong:qs.length-correct-blank,score:Math.round(correct/qs.length*100)};}
export function clearPractice(storage,user){try{storage.removeItem('jo-practice:v1:'+user);}catch{}}
