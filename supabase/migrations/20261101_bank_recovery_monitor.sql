-- Incremental upgrade after 20261031_competition_lifecycle.sql. No original data is deleted.
begin;
create or replace function public.jo_media_valid(v text,max_text integer) returns boolean language plpgsql immutable set search_path=pg_catalog as $$
declare m text[];stripped text;n integer:=0;
begin
 if v is null or length(v)>400000 then return false;end if;
 for m in select regexp_matches(v,'\[\[JIMG:(data:image/(png|jpeg|webp);base64,[A-Za-z0-9+/]+={0,2})\]\]','g') loop
 n:=n+1;if n>3 or length(m[1])>131072 then return false;end if;
 end loop;
 stripped:=regexp_replace(v,'\[\[JIMG:data:image/(png|jpeg|webp);base64,[A-Za-z0-9+/]+={0,2}\]\]','','g');
 return length(stripped)<=max_text and strpos(stripped,'[[JIMG:')=0;
end$$;
alter table public.jo_questions drop constraint if exists jo_questions_prompt_check;
alter table public.jo_questions drop constraint if exists jo_questions_explanation_check;
alter table public.jo_questions add constraint jo_questions_prompt_check check(length(trim(prompt))>0 and public.jo_media_valid(prompt,12000));
alter table public.jo_questions add constraint jo_questions_explanation_check check(public.jo_media_valid(explanation,12000));
alter table public.jo_competitions add column if not exists scoring_correct numeric not null default 1 check(scoring_correct between 0.01 and 100);
alter table public.jo_competitions add column if not exists scoring_wrong numeric not null default 0 check(scoring_wrong between -100 and 0);
alter table public.jo_competitions add column if not exists scoring_blank numeric not null default 0 check(scoring_blank between -100 and 0);
alter table public.jo_competitions add column if not exists rules text not null default '' check(length(rules)<=4000);
alter table public.jo_competitions add column if not exists award_rules text not null default '' check(length(award_rules)<=4000);
alter table public.jo_attempts add column if not exists grading jsonb not null default '{"correct":1,"wrong":0,"blank":0}';
alter table public.jo_attempts add column if not exists last_seen_at timestamptz;
alter table public.jo_attempts add column if not exists last_saved_at timestamptz;
create or replace function public.jo_grade(p_snapshot jsonb,p_answers jsonb,p_grading jsonb) returns numeric language sql immutable set search_path=pg_catalog as $$
select greatest(0,least(100,round(100.0*coalesce(sum(case when p_answers->>(q->>'id') is null then (p_grading->>'blank')::numeric when (p_answers->>(q->>'id'))::integer=(q->>'answer')::integer then (p_grading->>'correct')::numeric else (p_grading->>'wrong')::numeric end),0)/(greatest(jsonb_array_length(p_snapshot),1)*(p_grading->>'correct')::numeric),2))) from jsonb_array_elements(p_snapshot) q
$$;
revoke all on function public.jo_grade(jsonb,jsonb,jsonb) from public,anon,authenticated;
create table if not exists public.jo_import_batches(batch_id uuid primary key,actor_id uuid not null,competition_id uuid not null references public.jo_competitions on delete cascade,payload_hash text not null,inserted integer not null,skipped integer not null,created_at timestamptz not null default now());
alter table public.jo_import_batches enable row level security;
revoke all on public.jo_import_batches from public,anon,authenticated;
create or replace function public.jo_admin_import_questions(p_batch_id uuid,p_competition uuid,p_rows jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare prior public.jo_import_batches;c public.jo_competitions;item jsonb;opts jsonb;key text;pos integer;added integer:=0;skipped integer:=0;
begin
 if auth.uid() is null or not public.jo_is_admin() then raise exception 'Khusus Pengelola Olympiad';end if;
 if p_batch_id is null or p_competition is null or jsonb_typeof(p_rows) is distinct from 'array' then raise exception 'Daftar impor tidak valid';end if;
 if jsonb_array_length(p_rows) not between 1 and 100 or octet_length(p_rows::text)>4000000 then raise exception 'Maksimal 100 soal dan 4 MB per impor';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_batch_id::text,0));
 select * into prior from public.jo_import_batches where batch_id=p_batch_id;
 if found then
  if prior.actor_id<>auth.uid() or prior.competition_id<>p_competition or prior.payload_hash<>md5(p_rows::text) then raise exception 'ID batch telah dipakai untuk data lain';end if;
  return jsonb_build_object('inserted',0,'skipped',prior.inserted+prior.skipped);
 end if;
 select * into c from public.jo_competitions where id=p_competition for update;
 if not found or c.published or exists(select 1 from public.jo_attempts where competition_id=c.id) then raise exception 'Impor hanya pada draf tanpa pengerjaan';end if;
 select coalesce(max(position),0) into pos from public.jo_questions where competition_id=c.id;
 for item in select value from jsonb_array_elements(p_rows) loop
  opts:=item->'options';key:=upper(trim(coalesce(item->>'answer_key','')));
  if item->>'question_type' is distinct from 'mcq' or jsonb_typeof(opts) is distinct from 'array' then raise exception 'Impor Olympiad mendukung pilihan ganda';end if;
  if jsonb_array_length(opts) not between 4 and 5 or key !~ '^[A-E]$' or ascii(key)-65>=jsonb_array_length(opts) then raise exception 'Isi pilihan A–D/E dan kunci yang tersedia';end if;
  if trim(coalesce(item->>'prompt',''))='' or not public.jo_media_valid(item->>'prompt',12000) or not public.jo_media_valid(coalesce(item->>'explanation',''),12000) or octet_length(item::text)>1000000 then raise exception 'Pertanyaan/gambar tidak valid atau melebihi 1 MB';end if;
  if exists(select 1 from jsonb_array_elements(opts) x where jsonb_typeof(x)<>'string' or trim(x#>>'{}')='' or not public.jo_media_valid(x#>>'{}',4000)) then raise exception 'Pilihan tidak valid';end if;
  if exists(select 1 from public.jo_questions where competition_id=c.id and prompt=item->>'prompt' and options=opts and answer=ascii(key)-65 and explanation=coalesce(item->>'explanation','')) then skipped:=skipped+1;continue;end if;
  pos:=pos+1;if pos>200 then raise exception 'Maksimal 200 soal per kompetisi';end if;
  insert into public.jo_questions(competition_id,position,prompt,options,answer,explanation) values(c.id,pos,item->>'prompt',opts,ascii(key)-65,coalesce(item->>'explanation',''));added:=added+1;
 end loop;
 if (select coalesce(sum(octet_length(prompt)+octet_length(options::text)+octet_length(explanation)),0) from public.jo_questions where competition_id=c.id)>8000000 then raise exception 'Maksimal 8 MB soal dan gambar per kompetisi';end if;
 insert into public.jo_import_batches values(p_batch_id,auth.uid(),c.id,md5(p_rows::text),added,skipped,now());
 insert into public.jo_audit(actor,action,entity_id) values(auth.uid(),'import_questions',c.id);
 return jsonb_build_object('inserted',added,'skipped',skipped);
end$$;
create or replace function public.jo_monitor(p_competition uuid) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
begin
 if auth.uid() is null or not public.jo_is_admin() then raise exception 'Khusus Pengelola Olympiad';end if;
 perform 1 from public.jo_competitions where id=p_competition for share;
 update public.jo_attempts set submitted_at=deadline,score=public.jo_grade(snapshot,answers,grading) where competition_id=p_competition and submitted_at is null and clock_timestamp()>=deadline;
 return jsonb_build_object('server_time',clock_timestamp(),'registrations',coalesce((select jsonb_agg(to_jsonb(r)||jsonb_build_object('attempt',(select jsonb_build_object('id',a.id,'score',a.score,'submitted_at',a.submitted_at,'deadline',a.deadline,'departures',a.departures,'started_at',a.started_at,'last_seen_at',a.last_seen_at,'last_saved_at',a.last_saved_at,'question_count',jsonb_array_length(a.snapshot),'answered_count',(select count(*) from jsonb_each(a.answers) z where z.value<>'null'::jsonb)) from public.jo_attempts a where a.registration_id=r.id))) from public.jo_registrations r where r.competition_id=p_competition),'[]'::jsonb));
end$$;
create or replace function public.jo_exam(p_competition uuid,p_action text default 'get',p_payload jsonb default '{}') returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare c public.jo_competitions;r public.jo_registrations;a public.jo_attempts;t timestamptz; snap jsonb; q jsonb; key text;choice integer; rev integer;
begin
 if auth.uid() is null then raise exception 'Silakan masuk';end if;
 -- Shared competition lock serializes edits/publication against attempt creation.
 select * into c from public.jo_competitions where id=p_competition for share;
 select * into r from public.jo_registrations where competition_id=p_competition and user_id=auth.uid() for share;
 if not found or r.status<>'approved' then raise exception 'Akses kompetisi belum aktif';end if;
 select * into a from public.jo_attempts where registration_id=r.id for update;
 t:=clock_timestamp();
 if not found then
  if p_action='prepare' then return jsonb_build_object('ready',true,'title',c.title,'rules',c.rules,'award_rules',c.award_rules,'scoring_correct',c.scoring_correct,'scoring_wrong',c.scoring_wrong,'scoring_blank',c.scoring_blank,'starts_at',c.starts_at,'ends_at',c.ends_at);end if;
  if p_action<>'start' then raise exception 'Ujian belum dimulai';end if;
  if not c.published or t<c.starts_at or t>=c.ends_at then raise exception 'Ujian di luar jadwal';end if;
  select jsonb_agg(jsonb_build_object('id',id,'position',position,'prompt',prompt,'options',options,'answer',answer,'explanation',explanation) order by position) into snap from public.jo_questions where competition_id=c.id;
  if octet_length(snap::text)>8500000 then raise exception 'Ukuran snapshot melebihi batas';end if;
  if snap is null then raise exception 'Soal belum tersedia';end if;
  insert into public.jo_attempts(registration_id,user_id,competition_id,snapshot,deadline,grading,last_seen_at) values(r.id,auth.uid(),c.id,snap,least(t+make_interval(mins=>c.duration_minutes),c.ends_at),jsonb_build_object('correct',c.scoring_correct,'wrong',c.scoring_wrong,'blank',c.scoring_blank,'rules',c.rules,'award_rules',c.award_rules),t) on conflict(registration_id) do nothing;
  select * into a from public.jo_attempts where registration_id=r.id for update;
 end if;
 t:=clock_timestamp();
 if a.submitted_at is null then update public.jo_attempts set last_seen_at=t where id=a.id;end if;
 if a.submitted_at is null and t>=a.deadline then
  update public.jo_attempts set submitted_at=deadline,score=public.jo_grade(snapshot,answers,grading) where id=a.id returning * into a;
 end if;
 if a.submitted_at is null then
  if p_action='save' then
   key:=p_payload->>'question';rev:=(p_payload->>'revision')::integer;
   select value into q from jsonb_array_elements(a.snapshot) where value->>'id'=key;
   if q is null or rev is null or rev<1 then raise exception 'Jawaban tidak valid';end if;
   if p_payload->'choice'='null'::jsonb then choice:=null;else choice:=(p_payload->>'choice')::integer;end if;
   if choice is not null and (choice<0 or choice>=jsonb_array_length(q->'options')) then raise exception 'Pilihan tidak valid';end if;
   if rev>a.revision then update public.jo_attempts set answers=jsonb_set(answers,array[key],coalesce(to_jsonb(choice),'null'::jsonb)),revision=rev,last_saved_at=t where id=a.id returning * into a;end if;
  elsif p_action='submit' then
   update public.jo_attempts set submitted_at=t,score=public.jo_grade(snapshot,answers,grading) where id=a.id returning * into a;
  elsif p_action='leave' then
   update public.jo_attempts set departures=least(departures+1,10000) where id=a.id returning * into a;
  elsif p_action not in ('get','start') then raise exception 'Aksi tidak dikenal';end if;
 end if;
 return jsonb_build_object('attempt',a.id,'server_time',clock_timestamp(),'deadline',a.deadline,'submitted_at',a.submitted_at,'answers',a.answers,'revision',a.revision,'grading',a.grading,'score',case when c.results_published then a.score else null end,'questions',(select jsonb_agg(case when c.results_published and a.submitted_at is not null then value else value-'answer'-'explanation' end) from jsonb_array_elements(a.snapshot)));
end$$;
create or replace function public.jo_admin(p_action text,p_payload jsonb default '{}') returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare c public.jo_competitions;r public.jo_registrations;v_id uuid;opts jsonb;v_ref text;
begin
 if not public.jo_is_admin() or auth.uid() is null then raise exception 'Khusus Pengelola Olympiad';end if;
 if p_action='list' then
  return jsonb_build_object('competitions',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from public.jo_competitions x),'[]'::jsonb),'questions',coalesce((select jsonb_agg(to_jsonb(x) order by x.competition_id,x.position) from public.jo_questions x),'[]'::jsonb),'registrations',coalesce((select jsonb_agg(to_jsonb(x)||jsonb_build_object('attempt',(select jsonb_build_object('id',a.id,'score',a.score,'submitted_at',a.submitted_at,'deadline',a.deadline,'departures',a.departures,'started_at',a.started_at,'last_seen_at',a.last_seen_at,'last_saved_at',a.last_saved_at,'question_count',jsonb_array_length(a.snapshot),'answered_count',(select count(*) from jsonb_each(a.answers) z where z.value<>'null'::jsonb),'rank',case when a.submitted_at is not null then (select 1+count(distinct z.score) from public.jo_attempts z where z.competition_id=a.competition_id and z.submitted_at is not null and z.score>a.score) else null end) from public.jo_attempts a where a.registration_id=x.id),'certificate',(select to_jsonb(z) from public.jo_certificates z where z.registration_id=x.id)) order by x.created_at desc) from public.jo_registrations x),'[]'::jsonb),'payment',(select to_jsonb(x) from public.jo_payment_settings x));
 elsif p_action='payment_settings' then
  if length(trim(p_payload->>'bank')) not between 1 and 80 or length(trim(p_payload->>'account_number')) not between 3 and 40 or length(trim(p_payload->>'account_name')) not between 1 and 120 then raise exception 'Rekening belum lengkap';end if;
  update public.jo_payment_settings set bank=p_payload->>'bank',account_number=p_payload->>'account_number',account_name=p_payload->>'account_name' where id;
 elsif p_action='save_competition' then
  v_id:=coalesce(nullif(p_payload->>'id','')::uuid,gen_random_uuid());
  select * into c from public.jo_competitions where id=v_id for update;
  if c.id is not null and c.level<>(p_payload->>'level') and exists(select 1 from public.jo_registrations where competition_id=v_id) then raise exception 'Jenjang tidak dapat diubah setelah ada pendaftaran';end if;
  if exists(select 1 from public.jo_attempts where competition_id=v_id) then raise exception 'Kompetisi dengan pengerjaan sudah terkunci';end if;
  if coalesce((p_payload->>'published')::boolean,false) and not exists(select 1 from public.jo_questions where competition_id=v_id) then raise exception 'Tambahkan soal sebelum menerbitkan';end if;
  insert into public.jo_competitions(id,title,level,subject,description,fee,registration_opens,registration_closes,starts_at,ends_at,duration_minutes,published,scoring_correct,scoring_wrong,scoring_blank,rules,award_rules)
  values(v_id,trim(p_payload->>'title'),p_payload->>'level',trim(p_payload->>'subject'),coalesce(p_payload->>'description',''),(p_payload->>'fee')::bigint,(p_payload->>'registration_opens')::timestamptz,(p_payload->>'registration_closes')::timestamptz,(p_payload->>'starts_at')::timestamptz,(p_payload->>'ends_at')::timestamptz,(p_payload->>'duration_minutes')::integer,coalesce((p_payload->>'published')::boolean,false),coalesce((p_payload->>'scoring_correct')::numeric,c.scoring_correct,1),coalesce((p_payload->>'scoring_wrong')::numeric,c.scoring_wrong,0),coalesce((p_payload->>'scoring_blank')::numeric,c.scoring_blank,0),coalesce(p_payload->>'rules',c.rules,''),coalesce(p_payload->>'award_rules',c.award_rules,''))
  on conflict(id) do update set title=excluded.title,level=excluded.level,subject=excluded.subject,description=excluded.description,fee=excluded.fee,registration_opens=excluded.registration_opens,registration_closes=excluded.registration_closes,starts_at=excluded.starts_at,ends_at=excluded.ends_at,duration_minutes=excluded.duration_minutes,published=excluded.published,scoring_correct=excluded.scoring_correct,scoring_wrong=excluded.scoring_wrong,scoring_blank=excluded.scoring_blank,rules=excluded.rules,award_rules=excluded.award_rules;
 elsif p_action='delete_competition' then
  select * into c from public.jo_competitions where id=(p_payload->>'id')::uuid for update;
  if not found or c.published or exists(select 1 from public.jo_registrations where competition_id=c.id) then raise exception 'Hanya draf tanpa pendaftaran yang dapat dihapus';end if;
  delete from public.jo_competitions where id=c.id;v_id:=c.id;
 elsif p_action in ('save_question','delete_question') then
  select * into c from public.jo_competitions where id=(p_payload->>'competition_id')::uuid for update;
  if not found or c.published or exists(select 1 from public.jo_attempts where competition_id=c.id) then raise exception 'Soal hanya dapat diubah pada draf tanpa pengerjaan';end if;
  v_id:=coalesce(nullif(p_payload->>'id','')::uuid,gen_random_uuid());
  if exists(select 1 from public.jo_questions where id=v_id and competition_id<>c.id) then raise exception 'Soal bukan milik kompetisi';end if;
  if p_action='delete_question' then delete from public.jo_questions where id=v_id and competition_id=c.id;
  else
   opts:=p_payload->'options';
   if jsonb_typeof(opts)<>'array' or exists(select 1 from jsonb_array_elements(opts) x where jsonb_typeof(x)<>'string' or trim(x#>>'{}')='' or not public.jo_media_valid(x#>>'{}',4000)) then raise exception 'Pilihan jawaban tidak valid';end if;
   if not public.jo_media_valid(p_payload->>'prompt',12000) or not public.jo_media_valid(coalesce(p_payload->>'explanation',''),12000) or octet_length(p_payload::text)>1000000 then raise exception 'Teks atau gambar soal tidak valid / terlalu besar';end if;
   insert into public.jo_questions(id,competition_id,position,prompt,options,answer,explanation) values(v_id,c.id,(p_payload->>'position')::integer,trim(p_payload->>'prompt'),opts,(p_payload->>'answer')::integer,coalesce(p_payload->>'explanation','')) on conflict(id) do update set position=excluded.position,prompt=excluded.prompt,options=excluded.options,answer=excluded.answer,explanation=excluded.explanation;
   if (select coalesce(sum(octet_length(prompt)+octet_length(options::text)+octet_length(explanation)),0) from public.jo_questions where competition_id=c.id)>8000000 then raise exception 'Maksimal 8 MB soal dan gambar per kompetisi';end if;
  end if;
 elsif p_action in ('approve','reject') then
  select * into r from public.jo_registrations where id=(p_payload->>'registration_id')::uuid for update;
  if not found or r.status<>'review' then raise exception 'Pendaftaran tidak menunggu verifikasi';end if;
  v_ref:=trim(coalesce(p_payload->>'reference',''));
  if length(v_ref) not between 3 and 160 then raise exception 'Isi referensi penerimaan dana atau alasan penolakan';end if;
  update public.jo_registrations set status=case when p_action='approve' then 'approved' else 'rejected' end,payment_reference=case when p_action='approve' then v_ref else null end,review_note=v_ref,reviewed_at=clock_timestamp() where id=r.id;
  v_id:=r.id;
 elsif p_action='publish_results' then
  select * into c from public.jo_competitions where id=(p_payload->>'competition_id')::uuid for update;
  if not found or clock_timestamp()<c.ends_at then raise exception 'Tunggu seluruh jadwal ujian berakhir';end if;
  update public.jo_attempts set submitted_at=deadline,score=public.jo_grade(snapshot,answers,grading) where competition_id=c.id and submitted_at is null;
  update public.jo_competitions set results_published=true where id=c.id;v_id:=c.id;
 elsif p_action='issue_certificate' then
  select * into r from public.jo_registrations where id=(p_payload->>'registration_id')::uuid for update;
  select * into c from public.jo_competitions where id=r.competition_id;
  if r.id is null or r.status<>'approved' or not c.results_published or not exists(select 1 from public.jo_attempts where registration_id=r.id and submitted_at is not null) then raise exception 'Hasil peserta belum dapat diterbitkan';end if;
  insert into public.jo_certificates(registration_id,participant_name,competition_title,award) values(r.id,r.participant_name,c.title,trim(p_payload->>'award')) on conflict(registration_id) do nothing;v_id:=r.id;
 elsif p_action='revoke_certificate' then
  update public.jo_certificates set revoked=true where id=(p_payload->>'id')::uuid;v_id:=(p_payload->>'id')::uuid;
 else raise exception 'Aksi tidak dikenal';end if;
 insert into public.jo_audit(actor,action,entity_id) values(auth.uid(),p_action,v_id);
 return jsonb_build_object('ok',true,'id',v_id);
end$$;

revoke all on function public.jo_admin_import_questions(uuid,uuid,jsonb),public.jo_monitor(uuid) from public,anon;
grant execute on function public.jo_admin_import_questions(uuid,uuid,jsonb),public.jo_monitor(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
