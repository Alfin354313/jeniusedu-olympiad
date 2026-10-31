-- Run on the project configured by Olympiad /api/auth-config.
-- Current deployment shares the Panel project; jo_ tables are isolated.
-- Requires 20261028_participant_profiles.sql.
begin;
create or replace function public.jo_is_admin() returns boolean language sql stable set search_path=pg_catalog as $$select coalesce(lower(auth.jwt()->'app_metadata'->>'role') in ('admin','pengelola','administrator'),false)$$;
create table if not exists public.jo_competitions(
 id uuid primary key default gen_random_uuid(), title text not null check(length(trim(title)) between 3 and 160),
 level text not null check(level in ('SD','SMP','SMA')), subject text not null check(length(trim(subject)) between 1 and 80), description text not null default '' check(length(description)<=6000),
 fee bigint not null default 0 check(fee between 0 and 100000000), registration_opens timestamptz not null, registration_closes timestamptz not null,
 starts_at timestamptz not null, ends_at timestamptz not null, duration_minutes integer not null default 60 check(duration_minutes between 1 and 480),
 published boolean not null default false, results_published boolean not null default false, created_at timestamptz not null default now(),
 check(registration_closes>registration_opens and starts_at>=registration_closes and ends_at>starts_at)
);
create table if not exists public.jo_questions(
 id uuid primary key default gen_random_uuid(), competition_id uuid not null references public.jo_competitions on delete cascade,
 position integer not null check(position between 1 and 200), prompt text not null check(length(trim(prompt)) between 1 and 12000),
 options jsonb not null check(jsonb_typeof(options)='array' and jsonb_array_length(options) between 2 and 8), answer integer not null check(answer between 0 and 7), explanation text not null default '' check(length(explanation)<=12000),
 unique(competition_id,position),check(answer<jsonb_array_length(options))
);
create table if not exists public.jo_registrations(
 id uuid primary key default gen_random_uuid(), competition_id uuid not null references public.jo_competitions, user_id uuid not null references auth.users,
 participant_name text not null, school_level text not null, amount bigint not null check(amount>=0),
 status text not null check(status in ('pending','review','approved','rejected')), proof_path text, payment_reference text, review_note text,
 created_at timestamptz not null default now(), reviewed_at timestamptz, unique(competition_id,user_id)
);
create table if not exists public.jo_attempts(
 id uuid primary key default gen_random_uuid(), registration_id uuid not null unique references public.jo_registrations,
 user_id uuid not null references auth.users, competition_id uuid not null references public.jo_competitions,
 snapshot jsonb not null, answers jsonb not null default '{}', revision integer not null default 0,
 started_at timestamptz not null default now(), deadline timestamptz not null, submitted_at timestamptz,
 score numeric, departures integer not null default 0
);
create table if not exists public.jo_certificates(
 id uuid primary key default gen_random_uuid(),registration_id uuid not null unique references public.jo_registrations,
 participant_name text not null,competition_title text not null,award text not null check(length(trim(award)) between 1 and 160),issued_at timestamptz not null default now(),revoked boolean not null default false
);
create table if not exists public.jo_audit(id bigint generated always as identity primary key, actor uuid not null,action text not null,entity_id uuid,created_at timestamptz not null default now());
create table if not exists public.jo_payment_settings(id boolean primary key default true check(id),bank text not null default '',account_number text not null default '',account_name text not null default '');
insert into public.jo_payment_settings(id) values(true) on conflict do nothing;
create index if not exists jo_reg_user on public.jo_registrations(user_id);
create index if not exists jo_attempt_comp on public.jo_attempts(competition_id);
-- No participant SELECT on answer keys or attempt snapshots. All mutations use RPC.
alter table public.jo_competitions enable row level security;
alter table public.jo_questions enable row level security;
alter table public.jo_registrations enable row level security;
alter table public.jo_attempts enable row level security;
alter table public.jo_certificates enable row level security;
alter table public.jo_audit enable row level security;
alter table public.jo_payment_settings enable row level security;
revoke all on public.jo_competitions,public.jo_questions,public.jo_registrations,public.jo_attempts,public.jo_certificates,public.jo_audit,public.jo_payment_settings from anon,authenticated;
grant select on public.jo_competitions to anon,authenticated;
drop policy if exists jo_public_competitions on public.jo_competitions;
create policy jo_public_competitions on public.jo_competitions for select to anon,authenticated using(published or public.jo_is_admin());
grant select on public.olympiad_participant_profiles to authenticated;
drop policy if exists jo_admin_profiles on public.olympiad_participant_profiles;
create policy jo_admin_profiles on public.olympiad_participant_profiles for select to authenticated using(public.jo_is_admin());
create or replace function public.jo_grade(p_snapshot jsonb,p_answers jsonb) returns numeric language sql immutable set search_path=pg_catalog as $$
select round(100.0*count(*) filter(where (p_answers->>(q->>'id'))::integer=(q->>'answer')::integer)/greatest(jsonb_array_length(p_snapshot),1),2) from jsonb_array_elements(p_snapshot) q
$$;
revoke all on function public.jo_grade(jsonb,jsonb) from public,anon,authenticated;
create or replace function public.jo_register(p_competition uuid) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare c public.jo_competitions; p public.olympiad_participant_profiles; r public.jo_registrations; t timestamptz:=clock_timestamp();
begin
 if auth.uid() is null then raise exception 'Silakan masuk terlebih dahulu';end if;
 select * into c from public.jo_competitions where id=p_competition for update;
 if not found or not c.published then raise exception 'Kompetisi tidak tersedia';end if;
 select * into r from public.jo_registrations where competition_id=c.id and user_id=auth.uid();
 if found then return to_jsonb(r);end if;
 if t<c.registration_opens or t>=c.registration_closes then raise exception 'Pendaftaran belum dibuka atau sudah berakhir';end if;
 select * into p from public.olympiad_participant_profiles where id=auth.uid();
 if not found or p.school_level<>c.level then raise exception 'Lengkapi profil dan pilih kompetisi sesuai jenjang';end if;
 if c.fee>0 and not exists(select 1 from public.jo_payment_settings where length(trim(account_number))>0 and length(trim(bank))>0 and length(trim(account_name))>0) then raise exception 'Rekening pembayaran belum ditetapkan pengelola';end if;
 insert into public.jo_registrations(competition_id,user_id,participant_name,school_level,amount,status) values(c.id,auth.uid(),p.full_name,p.school_level,c.fee,case when c.fee=0 then 'approved' else 'pending' end) returning * into r;
 return to_jsonb(r);
end$$;
create or replace function public.jo_submit_proof(p_registration uuid,p_path text) returns void language plpgsql security definer set search_path=pg_catalog,public as $$
declare r public.jo_registrations;
begin
 select * into r from public.jo_registrations where id=p_registration and user_id=auth.uid() for update;
 if not found or r.status not in ('pending','rejected') or r.amount=0 then raise exception 'Pendaftaran tidak dapat menerima bukti';end if;
 if p_path not like auth.uid()::text||'/'||r.id::text||'/%' or not exists(select 1 from storage.objects where bucket_id='jo-payment-proofs' and name=p_path) then raise exception 'Bukti pembayaran tidak ditemukan';end if;
 update public.jo_registrations set proof_path=p_path,status='review',review_note=null where id=r.id;
end$$;
create or replace function public.jo_my_data() returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
begin
 if auth.uid() is null then raise exception 'Silakan masuk';end if;
 return jsonb_build_object('registrations',coalesce((select jsonb_agg(to_jsonb(r)||jsonb_build_object('competition',to_jsonb(c),'attempt',case when a.id is null then null else jsonb_build_object('id',a.id,'started_at',a.started_at,'deadline',a.deadline,'submitted_at',a.submitted_at,'score',case when c.results_published then a.score else null end,'rank',case when c.results_published and a.submitted_at is not null then (select 1+count(distinct z.score) from public.jo_attempts z where z.competition_id=c.id and z.submitted_at is not null and z.score>a.score) else null end) end,'certificate',(select to_jsonb(cert) from public.jo_certificates cert where cert.registration_id=r.id and not cert.revoked))) from public.jo_registrations r join public.jo_competitions c on c.id=r.competition_id left join public.jo_attempts a on a.registration_id=r.id where r.user_id=auth.uid()),'[]'::jsonb),'payment',(select to_jsonb(s)-'id' from public.jo_payment_settings s));
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
  if p_action<>'start' then raise exception 'Ujian belum dimulai';end if;
  if not c.published or t<c.starts_at or t>=c.ends_at then raise exception 'Ujian di luar jadwal';end if;
  select jsonb_agg(jsonb_build_object('id',id,'position',position,'prompt',prompt,'options',options,'answer',answer,'explanation',explanation) order by position) into snap from public.jo_questions where competition_id=c.id;
  if snap is null then raise exception 'Soal belum tersedia';end if;
  insert into public.jo_attempts(registration_id,user_id,competition_id,snapshot,deadline) values(r.id,auth.uid(),c.id,snap,least(t+make_interval(mins=>c.duration_minutes),c.ends_at)) on conflict(registration_id) do nothing;
  select * into a from public.jo_attempts where registration_id=r.id for update;
 end if;
 t:=clock_timestamp();
 if a.submitted_at is null and t>=a.deadline then
  update public.jo_attempts set submitted_at=deadline,score=public.jo_grade(snapshot,answers) where id=a.id returning * into a;
 end if;
 if a.submitted_at is null then
  if p_action='save' then
   key:=p_payload->>'question';rev:=(p_payload->>'revision')::integer;
   select value into q from jsonb_array_elements(a.snapshot) where value->>'id'=key;
   if q is null or rev is null or rev<1 then raise exception 'Jawaban tidak valid';end if;
   if p_payload->'choice'='null'::jsonb then choice:=null;else choice:=(p_payload->>'choice')::integer;end if;
   if choice is not null and (choice<0 or choice>=jsonb_array_length(q->'options')) then raise exception 'Pilihan tidak valid';end if;
   if rev>a.revision then update public.jo_attempts set answers=jsonb_set(answers,array[key],coalesce(to_jsonb(choice),'null'::jsonb)),revision=rev where id=a.id returning * into a;end if;
  elsif p_action='submit' then
   update public.jo_attempts set submitted_at=t,score=public.jo_grade(snapshot,answers) where id=a.id returning * into a;
  elsif p_action='leave' then
   update public.jo_attempts set departures=least(departures+1,10000) where id=a.id returning * into a;
  elsif p_action not in ('get','start') then raise exception 'Aksi tidak dikenal';end if;
 end if;
 return jsonb_build_object('attempt',a.id,'server_time',clock_timestamp(),'deadline',a.deadline,'submitted_at',a.submitted_at,'answers',a.answers,'revision',a.revision,'score',case when c.results_published then a.score else null end,'questions',(select jsonb_agg(case when c.results_published and a.submitted_at is not null then value else value-'answer'-'explanation' end) from jsonb_array_elements(a.snapshot)));
end$$;
create or replace function public.jo_verify_certificate(p_code uuid) returns jsonb language sql stable security definer set search_path=pg_catalog,public as $$select jsonb_build_object('id',id,'participant_name',participant_name,'competition_title',competition_title,'award',award,'issued_at',issued_at,'revoked',revoked) from public.jo_certificates where id=p_code$$;
create or replace function public.jo_admin(p_action text,p_payload jsonb default '{}') returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare c public.jo_competitions;r public.jo_registrations;v_id uuid;opts jsonb;v_ref text;
begin
 if not public.jo_is_admin() or auth.uid() is null then raise exception 'Khusus Pengelola Olympiad';end if;
 if p_action='list' then
  return jsonb_build_object('competitions',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from public.jo_competitions x),'[]'::jsonb),'questions',coalesce((select jsonb_agg(to_jsonb(x) order by x.competition_id,x.position) from public.jo_questions x),'[]'::jsonb),'registrations',coalesce((select jsonb_agg(to_jsonb(x)||jsonb_build_object('attempt',(select jsonb_build_object('id',a.id,'score',a.score,'submitted_at',a.submitted_at,'deadline',a.deadline,'departures',a.departures) from public.jo_attempts a where a.registration_id=x.id),'certificate',(select to_jsonb(z) from public.jo_certificates z where z.registration_id=x.id)) order by x.created_at desc) from public.jo_registrations x),'[]'::jsonb),'payment',(select to_jsonb(x) from public.jo_payment_settings x));
 elsif p_action='payment_settings' then
  if length(trim(p_payload->>'bank')) not between 1 and 80 or length(trim(p_payload->>'account_number')) not between 3 and 40 or length(trim(p_payload->>'account_name')) not between 1 and 120 then raise exception 'Rekening belum lengkap';end if;
  update public.jo_payment_settings set bank=p_payload->>'bank',account_number=p_payload->>'account_number',account_name=p_payload->>'account_name' where id;
 elsif p_action='save_competition' then
  v_id:=coalesce(nullif(p_payload->>'id','')::uuid,gen_random_uuid());
  select * into c from public.jo_competitions where id=v_id for update;
  if c.id is not null and c.level<>(p_payload->>'level') and exists(select 1 from public.jo_registrations where competition_id=v_id) then raise exception 'Jenjang tidak dapat diubah setelah ada pendaftaran';end if;
  if exists(select 1 from public.jo_attempts where competition_id=v_id) then raise exception 'Kompetisi dengan pengerjaan sudah terkunci';end if;
  if coalesce((p_payload->>'published')::boolean,false) and not exists(select 1 from public.jo_questions where competition_id=v_id) then raise exception 'Tambahkan soal sebelum menerbitkan';end if;
  insert into public.jo_competitions(id,title,level,subject,description,fee,registration_opens,registration_closes,starts_at,ends_at,duration_minutes,published)
  values(v_id,trim(p_payload->>'title'),p_payload->>'level',trim(p_payload->>'subject'),coalesce(p_payload->>'description',''),(p_payload->>'fee')::bigint,(p_payload->>'registration_opens')::timestamptz,(p_payload->>'registration_closes')::timestamptz,(p_payload->>'starts_at')::timestamptz,(p_payload->>'ends_at')::timestamptz,(p_payload->>'duration_minutes')::integer,coalesce((p_payload->>'published')::boolean,false))
  on conflict(id) do update set title=excluded.title,level=excluded.level,subject=excluded.subject,description=excluded.description,fee=excluded.fee,registration_opens=excluded.registration_opens,registration_closes=excluded.registration_closes,starts_at=excluded.starts_at,ends_at=excluded.ends_at,duration_minutes=excluded.duration_minutes,published=excluded.published;
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
   if jsonb_typeof(opts)<>'array' or exists(select 1 from jsonb_array_elements(opts) x where jsonb_typeof(x)<>'string' or length(trim(x#>>'{}')) not between 1 and 4000) then raise exception 'Pilihan jawaban tidak valid';end if;
   insert into public.jo_questions(id,competition_id,position,prompt,options,answer,explanation) values(v_id,c.id,(p_payload->>'position')::integer,trim(p_payload->>'prompt'),opts,(p_payload->>'answer')::integer,coalesce(p_payload->>'explanation','')) on conflict(id) do update set position=excluded.position,prompt=excluded.prompt,options=excluded.options,answer=excluded.answer,explanation=excluded.explanation;
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
  update public.jo_attempts set submitted_at=deadline,score=public.jo_grade(snapshot,answers) where competition_id=c.id and submitted_at is null;
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
revoke all on function public.jo_is_admin(),public.jo_register(uuid),public.jo_submit_proof(uuid,text),public.jo_my_data(),public.jo_exam(uuid,text,jsonb),public.jo_verify_certificate(uuid),public.jo_admin(text,jsonb) from public;
grant execute on function public.jo_is_admin() to anon,authenticated;
grant execute on function public.jo_register(uuid),public.jo_submit_proof(uuid,text),public.jo_my_data(),public.jo_exam(uuid,text,jsonb),public.jo_admin(text,jsonb) to authenticated;
grant execute on function public.jo_verify_certificate(uuid) to anon,authenticated;
-- Private proof files. New uploads only; no participant overwrite of reviewed evidence.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('jo-payment-proofs','jo-payment-proofs',false,3145728,array['image/jpeg','image/png','image/webp']) on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
create or replace function public.jo_can_upload_proof(p_name text) returns boolean language sql stable security definer set search_path=pg_catalog,public as $$select exists(select 1 from public.jo_registrations r where r.user_id=auth.uid() and r.status in ('pending','rejected') and r.amount>0 and split_part(p_name,'/',1)=auth.uid()::text and split_part(p_name,'/',2)=r.id::text)$$;
revoke all on function public.jo_can_upload_proof(text) from public;
grant execute on function public.jo_can_upload_proof(text) to authenticated;
drop policy if exists jo_proof_upload on storage.objects;
create policy jo_proof_upload on storage.objects for insert to authenticated with check(bucket_id='jo-payment-proofs' and public.jo_can_upload_proof(name));
drop policy if exists jo_proof_read on storage.objects;
create policy jo_proof_read on storage.objects for select to authenticated using(bucket_id='jo-payment-proofs' and (split_part(name,'/',1)=auth.uid()::text or public.jo_is_admin()));
notify pgrst,'reload schema';
commit;
