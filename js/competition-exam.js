import {getClient} from './participant-client.js';
import {escapeHtml as esc,rpc,richHtml} from './competition-service.js?v=2';
import {storeDraft,recoverDraft,clearDraft} from './competition-drafts.js?v=1';
const root=document.querySelector('#joExam'),id=new URLSearchParams(location.search).get('competition');
let client,userId,state,offset=0,queue=[],pendingRecovery=[],saving=false,failed=false,conflict=false,submitting=false,secondsTimer,poll,storageWarning=false;
const storage=()=>{try{return window.localStorage;}catch{return null;}};
const draftArgs=()=>({user:userId,competition:id,attempt:state.attempt,questions:state.questions,answers:state.answers,revision:state.revision});
const report=text=>{const e=root.querySelector('#examFeedback');if(e)e.textContent=text+(storageWarning?' Pemulihan lokal tidak tersedia di browser ini; tunggu semua jawaban tersimpan sebelum keluar.':'');};
function persist(){storageWarning=!storeDraft(storage(),{...draftArgs(),items:queue});}
function erase(){if(state)clearDraft(storage(),userId,id,state.attempt);}
async function call(action,payload={}){const data=await rpc(client,'jo_exam',{p_competition:id,p_action:action,p_payload:payload});if(data.server_time)offset=Date.parse(data.server_time)-Date.now();return data;}
function accept(data,recover=false){state=data;if(state.submitted_at){queue=[];pendingRecovery=[];erase();clearInterval(secondsTimer);clearInterval(poll);}else if(recover){pendingRecovery=recoverDraft(storage(),draftArgs());if(!pendingRecovery.length)erase();}render();}
function render(){
 root.innerHTML='<header class="jo-exam-header"><a href="peserta.html#jadwal">← Akun Peserta</a><strong>Ruang Ujian Olympiad</strong><span id="examClock" role="timer"></span></header><p id="examFeedback" role="status"></p>'+
 (pendingRecovery.length?'<section class="jo-recovery" role="status"><h2>Jawaban lokal ditemukan</h2><p>'+pendingRecovery.length+' jawaban belum selaras dengan server. Pilih sumber jawaban sebelum melanjutkan. Jawaban di server tetap ditampilkan saat ini.</p><button id="restoreDraft">Pulihkan Jawaban Lokal</button> <button id="discardDraft">Gunakan Jawaban Server</button></section>':'')+
 (state.submitted_at?'<div class="jo-notice"><h1>Jawaban telah dikumpulkan</h1><p>'+(state.score===null?'Hasil menunggu pengumuman pengelola.':'Nilai: '+esc(state.score)+' / 100')+'</p></div>':'<p>Kerjakan secara mandiri. Jawaban yang belum terkirim disimpan lokal di browser ini jika penyimpanan tersedia. Jangan berganti akun atau perangkat selama ujian.</p>')+
 state.questions.map((q,i)=>'<fieldset class="jo-card"><legend>Soal '+(i+1)+'</legend><div class="jo-description">'+richHtml(q.prompt)+'</div>'+q.options.map((option,j)=>'<label class="jo-option"><input type="radio" name="q'+q.id+'" data-question="'+q.id+'" value="'+j+'" '+(state.answers[q.id]===j?'checked ':'')+(state.submitted_at||pendingRecovery.length?'disabled':'')+'><span>'+String.fromCharCode(65+j)+'. '+richHtml(option)+'</span></label>').join('')+(q.answer!==undefined?'<p><strong>Kunci: '+String.fromCharCode(65+q.answer)+'</strong></p><div class="jo-description">'+richHtml(q.explanation)+'</div>':'')+'</fieldset>').join('')+
 (state.submitted_at?'':'<div class="jo-exam-actions"><button id="reloadExam" hidden>Muat Ulang & Selaraskan</button><button id="retrySave" hidden>Coba Simpan Lagi</button><button id="submitExam" '+(pendingRecovery.length?'disabled':'')+'>Kumpulkan Jawaban</button></div>');
 tick();
}
function tick(){const el=root.querySelector('#examClock');if(!el||!state)return;if(state.submitted_at){el.textContent='Selesai';return;}const remaining=Math.max(0,Math.ceil((Date.parse(state.deadline)-Date.now()-offset)/1000));el.textContent=Math.floor(remaining/60)+':'+String(remaining%60).padStart(2,'0');if(!remaining&&!submitting){submitting=true;call('get').then(data=>{accept(data);report('Waktu ujian berakhir. Hanya jawaban yang diterima server sebelum batas waktu yang dinilai.');}).catch(e=>report(e.message)).finally(()=>submitting=false);}}
async function flush(){
 if(saving||failed||conflict||pendingRecovery.length||!queue.length||state.submitted_at)return;
 saving=true;root.querySelector('#submitExam').disabled=true;report('Menyimpan jawaban…');
 while(queue.length&&!state.submitted_at){const item=queue[0];try{
  const next=await call('save',{question:item.id,choice:item.choice,revision:state.revision+1});
  if(next.submitted_at){accept(next);break;}
  if(next.answers[item.id]!==item.choice){conflict=true;throw Error('Ada perubahan dari sesi lain. Muat ulang lalu pilih sumber pemulihan.');}
  state.revision=next.revision;queue.shift();persist();
 }catch(e){failed=true;persist();report('Jawaban belum tersimpan: '+e.message);root.querySelector('#retrySave').hidden=conflict;root.querySelector('#reloadExam').hidden=!conflict;break;}}
 saving=false;if(!failed&&!state.submitted_at){report('Semua perubahan tersimpan di server.');root.querySelector('#submitExam').disabled=false;}
}
root.addEventListener('change',e=>{if(!e.target.matches('[data-question]')||!state||state.submitted_at||pendingRecovery.length||conflict)return;const q=state.questions.find(q=>q.id===e.target.dataset.question),choice=Number(e.target.value);if(!q||!Number.isInteger(choice)||choice<0||choice>=q.options.length)return;state.answers[q.id]=choice;queue.push({id:q.id,choice});persist();flush();});
root.addEventListener('click',async e=>{
 if(e.target.id==='restoreDraft'&&pendingRecovery.length){queue=pendingRecovery;pendingRecovery=[];for(const entry of queue)state.answers[entry.id]=entry.choice;persist();render();flush();}
 if(e.target.id==='discardDraft'){pendingRecovery=[];erase();render();report('Menggunakan jawaban yang sudah ada di server.');}
 if(e.target.id==='reloadExam')location.reload();
 if(e.target.id==='retrySave'){failed=false;e.target.hidden=true;flush();}
 if(e.target.id==='submitExam'&&!saving&&!queue.length&&!pendingRecovery.length&&!conflict&&!submitting){
  if(!confirm('Kumpulkan jawaban? Setelah dikumpulkan, jawaban tidak dapat diubah.'))return;
  submitting=true;e.target.disabled=true;try{accept(await call('submit'));}catch(err){report(err.message);e.target.disabled=false;}finally{submitting=false;}
 }
});
window.addEventListener('online',()=>{if(state&&!state.submitted_at&&!conflict&&!pendingRecovery.length){failed=false;const b=root.querySelector('#retrySave');if(b)b.hidden=true;flush();}});
window.addEventListener('beforeunload',e=>{if(queue.length||pendingRecovery.length){e.preventDefault();e.returnValue='';}});
document.addEventListener('visibilitychange',()=>{if(document.hidden&&state&&!state.submitted_at)call('leave').catch(()=>{});});
try{
 if(!/^[0-9a-f-]{36}$/i.test(id||''))throw Error('Kompetisi tidak valid.');
 client=await getClient();const {data,error}=await client.auth.getUser();
 if(error||!data.user){location.replace('login.html');}else{
  userId=data.user.id;
  try{accept(await call('get'),true);}catch(e){
   if(!/belum dimulai/i.test(e.message))throw e;
   const prep=await call('prepare');
   root.innerHTML='<section class="jo-card"><h1>Persiapan Ujian</h1><h2>'+esc(prep.title||'Jenius Olympiad')+'</h2><p class="jo-description">'+esc(prep.rules||'Kerjakan secara mandiri dan jujur. Waktu mengikuti server; perpindahan halaman dicatat.')+'</p><p>Benar: '+esc(prep.scoring_correct??1)+' · Salah: '+esc(prep.scoring_wrong??0)+' · Kosong: '+esc(prep.scoring_blank??0)+'. Nilai dinormalisasi menjadi 0–100, minimum 0. Nilai sama berbagi peringkat.</p><p class="jo-description">'+esc(prep.award_rules||'Penghargaan ditetapkan pengelola sesuai ketentuan kompetisi.')+'</p><label><input id="agreeExam" type="checkbox"> Saya memahami aturan dan siap mengerjakan secara mandiri.</label><p id="examFeedback" role="status"></p><button id="startExam">Mulai Ujian</button></section>';
   root.querySelector('#startExam').onclick=async event=>{if(!root.querySelector('#agreeExam').checked){report('Centang persetujuan sebelum memulai.');return;}event.target.disabled=true;try{accept(await call('start'),true);startTimers();}catch(err){report(err.message);event.target.disabled=false;}};
  }
  if(state)startTimers();
 }
}catch(e){root.innerHTML='<div class="jo-notice"><h1>Ujian belum dapat dibuka</h1><p>'+esc(e.message)+'</p><a href="peserta.html#jadwal">Kembali ke Jadwal & Ujian</a></div>';}
function startTimers(){if(state.submitted_at)return;secondsTimer=setInterval(tick,1000);poll=setInterval(()=>{if(!document.hidden&&!saving&&!queue.length&&!pendingRecovery.length&&!conflict&&!submitting){const revision=state.revision;call('get').then(data=>{if(!saving&&!queue.length&&!pendingRecovery.length&&!submitting&&state.revision===revision)accept(data);}).catch(e=>report(e.message));}},30000);}
