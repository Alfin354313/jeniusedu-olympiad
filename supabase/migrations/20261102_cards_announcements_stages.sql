begin;
create sequence if not exists public.jo_ticket_seq;
create or replace function public.jo_ticket_number(p_time timestamptz default now()) returns text language sql volatile security definer set search_path=pg_catalog,public as $$select 'JO-'||to_char(p_time at time zone 'Asia/Jakarta','YYYY')||'-'||lpad(n::text,greatest(6,length(n::text)),'0') from (select nextval('public.jo_ticket_seq') n) s$$;
alter table public.jo_registrations add column if not exists participant_no text;
update public.jo_registrations set participant_no=public.jo_ticket_number(created_at) where participant_no is null;
alter table public.jo_registrations alter column participant_no set default public.jo_ticket_number();
alter table public.jo_registrations alter column participant_no set not null;
create unique index if not exists jo_participant_no_unique on public.jo_registrations(participant_no);
alter table public.jo_registrations drop constraint if exists jo_registrations_status_check;
alter table public.jo_registrations add constraint jo_registrations_status_check check(status in ('pending','review','approved','rejected','cancelled'));
alter table public.jo_competitions add column if not exists round_kind text not null default 'single' check(round_kind in ('single','preliminary','final'));
alter table public.jo_competitions add column if not exists parent_competition_id uuid references public.jo_competitions(id);
alter table public.jo_competitions drop constraint if exists jo_round_parent_check;
alter table public.jo_competitions add constraint jo_round_parent_check check((round_kind='final' and parent_competition_id is not null and parent_competition_id<>id and fee=0) or (round_kind<>'final' and parent_competition_id is null));
create table if not exists public.jo_qualifications(parent_registration_id uuid not null references public.jo_registrations(id),final_competition_id uuid not null references public.jo_competitions(id),final_registration_id uuid not null unique references public.jo_registrations(id),active boolean not null default true,decided_by uuid not null references auth.users(id),decided_at timestamptz not null default now(),note text not null check(length(note) between 3 and 500),primary key(parent_registration_id,final_competition_id));
create table if not exists public.jo_announcements(id uuid primary key default gen_random_uuid(),title text not null check(length(trim(title)) between 1 and 160),body text not null check(length(trim(body)) between 1 and 8000),audience text not null check(audience in ('public','participants')),competition_id uuid references public.jo_competitions(id),published boolean not null default false,pinned boolean not null default false,publish_at timestamptz not null default now(),expires_at timestamptz,updated_at timestamptz not null default now(),updated_by uuid not null references auth.users(id),check(expires_at is null or expires_at>publish_at));
alter table public.jo_qualifications enable row level security;
alter table public.jo_announcements enable row level security;
revoke all on public.jo_qualifications,public.jo_announcements,public.jo_ticket_seq from public,anon,authenticated;
create or replace function public.jo_participant_card(p_registration uuid) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare result jsonb;
begin
 if auth.uid() is null then raise exception 'Silakan masuk ke akun peserta';end if;
 select jsonb_build_object('participant_no',r.participant_no,'participant_name',r.participant_name,'school_level',r.school_level,'competition_title',c.title,'subject',c.subject,'round_kind',c.round_kind,'starts_at',c.starts_at,'ends_at',c.ends_at,'duration_minutes',c.duration_minutes) into result from public.jo_registrations r join public.jo_competitions c on c.id=r.competition_id where r.id=p_registration and r.status='approved' and (r.user_id=auth.uid() or public.jo_is_admin());
 if result is null then raise exception 'Kartu tidak tersedia atau pendaftaran belum aktif';end if;
 return result;
end$$;
create or replace function public.jo_announcements(p_competition uuid default null) returns jsonb language sql stable security definer set search_path=pg_catalog,public as $$
select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'title',a.title,'body',a.body,'publish_at',a.publish_at,'pinned',a.pinned,'competition_id',a.competition_id) order by a.pinned desc,a.publish_at desc),'[]'::jsonb) from public.jo_announcements a where a.published and a.publish_at<=now() and (a.expires_at is null or a.expires_at>now()) and (p_competition is null or a.competition_id is null or a.competition_id=p_competition) and (a.audience='public' or (auth.uid() is not null and ((a.competition_id is null and exists(select 1 from public.olympiad_participant_profiles p where p.id=auth.uid())) or exists(select 1 from public.jo_registrations r where r.user_id=auth.uid() and r.competition_id=a.competition_id and r.status='approved'))))
$$;
create or replace function public.jo_public_announcements() returns jsonb language sql stable security definer set search_path=pg_catalog,public as $$
select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'title',a.title,'body',a.body,'publish_at',a.publish_at,'pinned',a.pinned,'competition_id',a.competition_id) order by a.pinned desc,a.publish_at desc),'[]'::jsonb) from public.jo_announcements a where a.audience='public' and a.published and a.publish_at<=now() and (a.expires_at is null or a.expires_at>now())
$$;
revoke all on function public.jo_public_announcements() from public;
grant execute on function public.jo_public_announcements() to anon,authenticated;
create or replace function public.jo_announcement_admin(p_action text,p_payload jsonb default '{}') returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_id uuid;
begin
 if auth.uid() is null or not public.jo_is_admin() then raise exception 'Khusus Pengelola Olympiad';end if;
 if p_action='list' then return coalesce((select jsonb_agg(to_jsonb(a) order by a.updated_at desc) from public.jo_announcements a),'[]'::jsonb);end if;
 v_id:=coalesce(nullif(p_payload->>'id','')::uuid,gen_random_uuid());
 if p_action='save' then
 insert into public.jo_announcements(id,title,body,audience,competition_id,published,pinned,publish_at,expires_at,updated_by) values(v_id,trim(p_payload->>'title'),trim(p_payload->>'body'),p_payload->>'audience',nullif(p_payload->>'competition_id','')::uuid,coalesce((p_payload->>'published')::boolean,false),coalesce((p_payload->>'pinned')::boolean,false),coalesce(nullif(p_payload->>'publish_at','')::timestamptz,now()),nullif(p_payload->>'expires_at','')::timestamptz,auth.uid()) on conflict(id) do update set title=excluded.title,body=excluded.body,audience=excluded.audience,competition_id=excluded.competition_id,published=excluded.published,pinned=excluded.pinned,publish_at=excluded.publish_at,expires_at=excluded.expires_at,updated_at=now(),updated_by=auth.uid();
 elsif p_action='delete' then delete from public.jo_announcements where id=v_id;
 else raise exception 'Aksi tidak dikenal';end if;
 insert into public.jo_audit(actor,action,entity_id) values(auth.uid(),'announcement_'||p_action,v_id);return jsonb_build_object('id',v_id);
end$$;
create or replace function public.jo_stage_admin(p_action text,p_payload jsonb default '{}') returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare f public.jo_competitions;p public.jo_competitions;r public.jo_registrations;fr public.jo_registrations;rid uuid;ids jsonb;v_note text;total integer:=0;
begin
 if auth.uid() is null or not public.jo_is_admin() then raise exception 'Khusus Pengelola Olympiad';end if;
 select * into f from public.jo_competitions where id=(p_payload->>'final_id')::uuid for update;
 if not found or f.round_kind<>'final' then raise exception 'Pilih kompetisi final';end if;
 select * into p from public.jo_competitions where id=f.parent_competition_id for share;
 if p_action='list' then return jsonb_build_object('final',to_jsonb(f),'parent',to_jsonb(p),'candidates',coalesce((select jsonb_agg(jsonb_build_object('id',candidate.id,'participant_no',candidate.participant_no,'participant_name',candidate.participant_name,'score',a.score,'rank',(select 1+count(distinct z.score) from public.jo_attempts z join public.jo_registrations zr on zr.id=z.registration_id where z.competition_id=p.id and zr.status='approved' and z.submitted_at is not null and z.score>a.score),'qualified',coalesce(q.active,false),'final_registration_id',q.final_registration_id) order by a.score desc,candidate.participant_no) from public.jo_registrations candidate join public.jo_attempts a on a.registration_id=candidate.id left join public.jo_qualifications q on q.parent_registration_id=candidate.id and q.final_competition_id=f.id where candidate.competition_id=p.id and candidate.status='approved' and a.submitted_at is not null),'[]'::jsonb));end if;
 if p_action not in ('promote','revoke') then raise exception 'Aksi tidak dikenal';end if;
 if not p.results_published or not f.published or clock_timestamp()>=f.starts_at then raise exception 'Hasil penyisihan harus diumumkan; final harus terbit dan belum dimulai';end if;
 ids:=p_payload->'registration_ids';v_note:=trim(p_payload->>'note');
 if ids is null or jsonb_typeof(ids)<>'array' or jsonb_array_length(ids) not between 1 and 1000 or v_note is null or length(v_note) not between 3 and 500 then raise exception 'Pilih 1–1000 peserta dan isi alasan keputusan';end if;
 for rid in select distinct value::uuid from jsonb_array_elements_text(ids) order by value::uuid loop
 select * into r from public.jo_registrations where id=rid and competition_id=p.id and status='approved' for update;
 if not found or not exists(select 1 from public.jo_attempts where registration_id=r.id and submitted_at is not null) then raise exception 'Peserta bukan kandidat penyisihan yang sah';end if;
 select * into fr from public.jo_registrations where competition_id=f.id and user_id=r.user_id for update;
 if fr.id is not null and exists(select 1 from public.jo_attempts where registration_id=fr.id) then raise exception 'Keputusan terkunci karena peserta sudah memulai final';end if;
 if p_action='promote' then
 insert into public.jo_registrations(competition_id,user_id,participant_name,school_level,amount,status,reviewed_at) values(f.id,r.user_id,r.participant_name,r.school_level,0,'approved',now()) on conflict(competition_id,user_id) do update set status='approved',reviewed_at=now() returning * into fr;
 insert into public.jo_qualifications(parent_registration_id,final_competition_id,final_registration_id,active,decided_by,note) values(r.id,f.id,fr.id,true,auth.uid(),v_note) on conflict(parent_registration_id,final_competition_id) do update set active=true,decided_by=auth.uid(),decided_at=now(),note=v_note;
 else
 if not exists(select 1 from public.jo_qualifications where parent_registration_id=r.id and final_competition_id=f.id and active) then raise exception 'Peserta belum ditetapkan lolos';end if;
 update public.jo_registrations set status='cancelled' where id=fr.id;
 update public.jo_qualifications set active=false,decided_by=auth.uid(),decided_at=now(),note=v_note where parent_registration_id=r.id and final_competition_id=f.id;
 end if;
 insert into public.jo_audit(actor,action,entity_id) values(auth.uid(),'qualification_'||p_action,fr.id);total:=total+1;
 end loop;
 return jsonb_build_object('processed',total);
end$$;
create or replace function public.jo_register(p_competition uuid) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare c public.jo_competitions; p public.olympiad_participant_profiles; r public.jo_registrations; t timestamptz:=clock_timestamp();
begin
 if auth.uid() is null then raise exception 'Silakan masuk terlebih dahulu';end if;
 select * into c from public.jo_competitions where id=p_competition for update;
 if not found or not c.published then raise exception 'Kompetisi tidak tersedia';end if;
 select * into r from public.jo_registrations where competition_id=c.id and user_id=auth.uid();
 if found then return to_jsonb(r);end if;
 if c.round_kind='final' then raise exception 'Final khusus peserta lolos; tidak ada pembelian ulang';end if;
 if t<c.registration_opens or t>=c.registration_closes then raise exception 'Pendaftaran belum dibuka atau sudah berakhir';end if;
 select * into p from public.olympiad_participant_profiles where id=auth.uid();
 if not found or p.school_level<>c.level then raise exception 'Lengkapi profil dan pilih kompetisi sesuai jenjang';end if;
 if c.fee>0 and not exists(select 1 from public.jo_payment_settings where length(trim(account_number))>0 and length(trim(bank))>0 and length(trim(account_name))>0) then raise exception 'Rekening pembayaran belum ditetapkan pengelola';end if;
 insert into public.jo_registrations(competition_id,user_id,participant_name,school_level,amount,status) values(c.id,auth.uid(),p.full_name,p.school_level,c.fee,case when c.fee=0 then 'approved' else 'pending' end) returning * into r;
 return to_jsonb(r);
end$$;
create or replace function public.jo_admin(p_action text,p_payload jsonb default '{}') returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare c public.jo_competitions;r public.jo_registrations;v_id uuid;opts jsonb;v_ref text;parent public.jo_competitions;kind text;parent_id uuid;
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
  kind:=coalesce(p_payload->>'round_kind',c.round_kind,'single');parent_id:=nullif(p_payload->>'parent_competition_id','')::uuid;
  if kind='final' then
   select * into parent from public.jo_competitions where id=parent_id for share;
   if not found or parent.round_kind='final' or parent.id=v_id or parent.level<>p_payload->>'level' or (p_payload->>'starts_at')::timestamptz<=parent.ends_at then raise exception 'Final harus mengikuti penyisihan dengan jenjang sama dan jadwal setelah penyisihan';end if;
   p_payload:=p_payload||jsonb_build_object('fee',0,'registration_opens',parent.ends_at,'registration_closes',p_payload->>'starts_at');
  elsif parent_id is not null then raise exception 'Induk kompetisi hanya untuk final';end if;
  if c.id is not null and (c.round_kind<>kind or c.parent_competition_id is distinct from parent_id) and exists(select 1 from public.jo_registrations where competition_id=v_id) then raise exception 'Tahapan terkunci setelah ada pendaftaran';end if;
  if exists(select 1 from public.jo_competitions child where child.parent_competition_id=v_id and (child.level<>p_payload->>'level' or child.starts_at<=(p_payload->>'ends_at')::timestamptz or kind='final')) then raise exception 'Perubahan tidak sesuai jadwal atau jenjang final terkait';end if;
  insert into public.jo_competitions(id,title,level,subject,description,fee,registration_opens,registration_closes,starts_at,ends_at,duration_minutes,published,scoring_correct,scoring_wrong,scoring_blank,rules,award_rules,round_kind,parent_competition_id)
  values(v_id,trim(p_payload->>'title'),p_payload->>'level',trim(p_payload->>'subject'),coalesce(p_payload->>'description',''),(p_payload->>'fee')::bigint,(p_payload->>'registration_opens')::timestamptz,(p_payload->>'registration_closes')::timestamptz,(p_payload->>'starts_at')::timestamptz,(p_payload->>'ends_at')::timestamptz,(p_payload->>'duration_minutes')::integer,coalesce((p_payload->>'published')::boolean,false),coalesce((p_payload->>'scoring_correct')::numeric,c.scoring_correct,1),coalesce((p_payload->>'scoring_wrong')::numeric,c.scoring_wrong,0),coalesce((p_payload->>'scoring_blank')::numeric,c.scoring_blank,0),coalesce(p_payload->>'rules',c.rules,''),coalesce(p_payload->>'award_rules',c.award_rules,''),kind,parent_id)
  on conflict(id) do update set title=excluded.title,level=excluded.level,subject=excluded.subject,description=excluded.description,fee=excluded.fee,registration_opens=excluded.registration_opens,registration_closes=excluded.registration_closes,starts_at=excluded.starts_at,ends_at=excluded.ends_at,duration_minutes=excluded.duration_minutes,published=excluded.published,scoring_correct=excluded.scoring_correct,scoring_wrong=excluded.scoring_wrong,scoring_blank=excluded.scoring_blank,rules=excluded.rules,award_rules=excluded.award_rules,round_kind=excluded.round_kind,parent_competition_id=excluded.parent_competition_id;
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
revoke all on function public.jo_ticket_number(timestamptz),public.jo_participant_card(uuid),public.jo_announcements(uuid),public.jo_announcement_admin(text,jsonb),public.jo_stage_admin(text,jsonb) from public,anon,authenticated;
grant execute on function public.jo_announcements(uuid) to anon,authenticated;
grant execute on function public.jo_participant_card(uuid),public.jo_announcement_admin(text,jsonb),public.jo_stage_admin(text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
