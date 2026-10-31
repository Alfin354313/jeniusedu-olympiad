const fs=require('fs'),path=require('path'),assert=require('node:assert/strict');
const {JSDOM}=require(process.env.JSDOM_MODULE||'jsdom');
const source=fs.readFileSync('js/olympiad.js','utf8');
for(const page of ['home','kompetisi','jadwal','panduan','pengumuman','faq','blog','article']){
 const dom=new JSDOM('<body data-page="'+page+'"><div id="app"></div></body>',{url:'https://example.test/'+(page==='article'?'artikel.html?artikel=percaya-diri':page+'.html'),runScripts:'outside-only'});
 dom.window.eval(source);const d=dom.window.document;assert(d.querySelector('header'));assert(d.querySelector('main'));assert(d.querySelector('footer'));
 if(page==='home'){assert(d.querySelector('.arena-intro'));assert(!d.querySelector('#promo'));}
 if(page==='kompetisi'){d.querySelector('[data-level="SD"]').click();assert.equal([...d.querySelectorAll('.competition-card')].filter(x=>!x.hidden).length,2);const q=d.querySelector('#competitionSearch');q.value='tidakada';q.dispatchEvent(new dom.window.Event('input'));assert.equal(d.querySelector('#competitionEmpty').hidden,false);}
 dom.window.close();
}
(async()=>{
 const html=fs.readFileSync('peserta.html','utf8');const dom=new JSDOM(html,{url:'https://example.test/peserta.html#hasil',runScripts:'outside-only'});const w=dom.window;
 let saved;w.getClient=async()=>({auth:{getUser:async()=>({data:{user:{id:'test',email:'peserta@example.test',user_metadata:{full_name:'<img src=x onerror=alert(1)>'}}}}),onAuthStateChange:()=>{},signOut:async()=>({})},from:()=>({select:()=>({eq:()=>({maybeSingle:async()=>({data:{full_name:'Peserta',school_level:'SMP'}})})}),upsert:async row=>{saved=row;return {}}})});w.message=e=>e.message;w.callbackUrl=()=>'';
 w.eval(fs.readFileSync('js/participant-account.js','utf8').replace(/^import .*\n/m,''));await new Promise(r=>setTimeout(r,20));const d=w.document;
 assert.equal(d.querySelector('.participant-hero').hidden,true);assert.match(d.querySelector('#competitionArea').textContent,/Hasil & Penghargaan/);assert(!d.querySelector('#welcomeName img'));
 for(const panel of ['my','schedule','announcements','profile','dashboard']){d.querySelector('[data-panel="'+panel+'"]').click();assert.equal(d.querySelectorAll('[aria-current="page"]').length,1);assert.equal(d.querySelector('#profilePanel').hidden,panel!=='profile');assert.equal(d.querySelector('#dashboardPanels').hidden,panel!=='dashboard');}
 d.querySelector('[data-panel="profile"]').click();d.querySelector('#name').value='Nama Baru';d.querySelector('#profileForm').dispatchEvent(new w.Event('submit',{cancelable:true}));await new Promise(r=>setTimeout(r,10));assert.equal(saved.full_name,'Nama Baru');assert.equal(saved.school_level,'SMP');
 d.querySelector('[data-panel="my"]').click();w.location.hash='hasil';w.dispatchEvent(new w.Event('hashchange'));assert.match(d.querySelector('#competitionArea').textContent,/Hasil & Penghargaan/);assert(!d.querySelector('#competitionArea button'));
 dom.window.close();console.log('PASS: eight public pages, filters, participant separate panels/deep links, escaped name, profile save');
})().catch(e=>{console.error(e);process.exitCode=1});
