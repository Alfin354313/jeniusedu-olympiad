-- Requires 20261102_cards_announcements_stages.sql. Run one copy on Olympiad's configured project.
begin;
create table if not exists public.jo_support_settings(id boolean primary key default true check(id),whatsapp text not null default '' check(whatsapp='' or whatsapp ~ '^[1-9][0-9]{7,14}$'),email text not null default '' check(length(email)<=160 and (email='' or email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$')),hours text not null default '' check(length(hours)<=240),updated_at timestamptz not null default now());
insert into public.jo_support_settings(id) values(true) on conflict do nothing;
alter table public.jo_support_settings enable row level security;
revoke all on public.jo_support_settings from public,anon,authenticated;
create or replace function public.jo_support() returns jsonb language sql stable security definer set search_path=pg_catalog,public as $$select to_jsonb(s)-'id'-'updated_at' from public.jo_support_settings s where id$$;
create or replace function public.jo_support_admin(p_payload jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
begin
 if auth.uid() is null or not public.jo_is_admin() then raise exception 'Khusus Pengelola Olympiad';end if;
 update public.jo_support_settings set whatsapp=trim(coalesce(p_payload->>'whatsapp','')),email=trim(coalesce(p_payload->>'email','')),hours=trim(coalesce(p_payload->>'hours','')),updated_at=now() where id;
 insert into public.jo_audit(actor,action) values(auth.uid(),'support_settings');return public.jo_support();
end$$;
create or replace function public.jo_participant_updates() returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare t timestamptz:=clock_timestamp();items jsonb;
begin
 if auth.uid() is null then raise exception 'Silakan masuk';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'kind',x.kind,'title',x.title,'body',x.body,'target',x.target,'at',x.remind_at) order by x.priority,x.remind_at),'[]'::jsonb) into items from (
 select r.id,'payment'::text kind,c.title,'Selesaikan transfer dan unggah bukti pembayaran.'::text body,'my'::text target,1 priority,r.created_at remind_at from public.jo_registrations r join public.jo_competitions c on c.id=r.competition_id where r.user_id=auth.uid() and r.status in ('pending','rejected') and r.amount>0 and c.published and c.ends_at>t
 union all select r.id,'review',c.title,'Bukti menunggu verifikasi pengelola. Tidak perlu transfer ulang.','my',3,r.created_at from public.jo_registrations r join public.jo_competitions c on c.id=r.competition_id where r.user_id=auth.uid() and r.status='review'
 union all select r.id,'exam',c.title,case when c.starts_at<=t then 'Ujian sedang dibuka. Periksa batas waktu dan lanjutkan melalui Jadwal & Ujian.' else 'Ujian dimulai dalam 24 jam. Siapkan perangkat dan koneksi.' end,'schedule',0,c.starts_at from public.jo_registrations r join public.jo_competitions c on c.id=r.competition_id left join public.jo_attempts a on a.registration_id=r.id where r.user_id=auth.uid() and r.status='approved' and c.published and c.ends_at>t and c.starts_at<=t+interval '24 hours' and a.submitted_at is null and (a.id is null or a.deadline>t)
 union all select r.id,'final',c.title,'Kamu ditetapkan lolos. Akses final aktif tanpa pembayaran ulang.','schedule',2,c.starts_at from public.jo_registrations r join public.jo_competitions c on c.id=r.competition_id where r.user_id=auth.uid() and r.status='approved' and c.round_kind='final' and c.published and c.ends_at>t
 union all select r.id,'result',c.title,'Hasil kompetisi sudah diumumkan. Lihat nilai dan penghargaanmu.','awards',4,c.ends_at from public.jo_registrations r join public.jo_competitions c on c.id=r.competition_id join public.jo_attempts a on a.registration_id=r.id where r.user_id=auth.uid() and r.status='approved' and c.results_published and a.submitted_at is not null
 ) x;
 return jsonb_build_object('server_time',t,'items',items);
end$$;
create or replace function public.jo_report(p_competition uuid) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare c public.jo_competitions;regs jsonb;exams jsonb;grades jsonb;bands jsonb;
begin
 if auth.uid() is null or not public.jo_is_admin() then raise exception 'Khusus Pengelola Olympiad';end if;
 select * into c from public.jo_competitions where id=p_competition;
 if not found then raise exception 'Kompetisi tidak ditemukan';end if;
 select jsonb_build_object('total',count(*),'approved',count(*) filter(where status='approved'),'pending',count(*) filter(where status='pending'),'review',count(*) filter(where status='review'),'rejected',count(*) filter(where status='rejected'),'cancelled',count(*) filter(where status='cancelled'),'paid_count',count(*) filter(where status='approved' and amount>0),'paid_amount',coalesce(sum(amount) filter(where status='approved' and amount>0),0),'unverified_amount',coalesce(sum(amount) filter(where status in ('pending','review','rejected')),0)) into regs from public.jo_registrations where competition_id=c.id;
 select jsonb_build_object('started',count(*),'submitted',count(*) filter(where a.submitted_at is not null),'in_progress',count(*) filter(where a.submitted_at is null and a.deadline>clock_timestamp()),'expired_unsubmitted',count(*) filter(where a.submitted_at is null and a.deadline<=clock_timestamp()),'not_started',(select count(*) from public.jo_registrations r where r.competition_id=c.id and r.status='approved' and not exists(select 1 from public.jo_attempts z where z.registration_id=r.id))) into exams from public.jo_attempts a join public.jo_registrations r on r.id=a.registration_id where a.competition_id=c.id and r.status='approved';
 select jsonb_build_object('count',count(*),'average',round(avg(a.score),2),'min',min(a.score),'max',max(a.score)) into grades from public.jo_attempts a join public.jo_registrations r on r.id=a.registration_id where a.competition_id=c.id and r.status='approved' and a.submitted_at is not null;
 select jsonb_agg(jsonb_build_object('label',b.label,'count',(select count(*) from public.jo_attempts a join public.jo_registrations r on r.id=a.registration_id where a.competition_id=c.id and r.status='approved' and a.submitted_at is not null and a.score>=b.lo and (a.score<b.hi or b.hi=101))) order by b.lo) into bands from (values(0,20,'0–<20'),(20,40,'20–<40'),(40,60,'40–<60'),(60,80,'60–<80'),(80,101,'80–100')) b(lo,hi,label);
 return jsonb_build_object('competition',to_jsonb(c),'generated_at',clock_timestamp(),'registrations',regs,'exams',exams,'grades',grades,'distribution',bands,'qualified',(select count(*) from public.jo_qualifications q join public.jo_registrations r on r.id=q.parent_registration_id where r.competition_id=c.id and q.active),'certificates',(select count(*) from public.jo_certificates cert join public.jo_registrations r on r.id=cert.registration_id where r.competition_id=c.id and not cert.revoked));
end$$;
create table if not exists public.jo_certificate_batches(id uuid primary key,actor uuid not null references auth.users,competition_id uuid not null references public.jo_competitions,request_hash text not null,result jsonb not null,created_at timestamptz not null default now());
alter table public.jo_certificate_batches enable row level security;
revoke all on public.jo_certificate_batches from public,anon,authenticated;
create or replace function public.jo_certificate_batch(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare c public.jo_competitions;r public.jo_registrations;a public.jo_attempts;cert public.jo_certificates;prior public.jo_certificate_batches;award text:=trim(p_payload->>'award');item jsonb;rows jsonb;batch_id uuid;request_hash text;expected text;issued integer:=0;skipped integer:=0;result jsonb;
begin
 if auth.uid() is null or not public.jo_is_admin() then raise exception 'Khusus Pengelola Olympiad';end if;
 if award is null or length(award) not between 1 and 160 then raise exception 'Isi penghargaan 1–160 karakter';end if;
 if p_action='issue' then
 batch_id:=(p_payload->>'batch_id')::uuid;if batch_id is null then raise exception 'Kode batch wajib diisi';end if;
 perform pg_advisory_xact_lock(hashtextextended(batch_id::text,0));
 request_hash:=md5(jsonb_build_array(p_payload->>'competition_id',award,p_payload->'rows')::text);
 select * into prior from public.jo_certificate_batches where id=batch_id;
 if found then
 if prior.actor<>auth.uid() or prior.request_hash<>request_hash then raise exception 'Batch sudah digunakan untuk data lain';end if;
 return prior.result||jsonb_build_object('replayed',true);
 end if;
 end if;
 select * into c from public.jo_competitions where id=(p_payload->>'competition_id')::uuid for update;
 if not found or not c.results_published or clock_timestamp()<c.ends_at then raise exception 'Umumkan hasil setelah ujian berakhir sebelum membuat sertifikat massal';end if;
 if p_action='preview' then
 select coalesce(jsonb_agg(to_jsonb(x) order by x.existing,x.participant_name,x.id),'[]'::jsonb) into rows from (
 select pr.id,pr.participant_no,pr.participant_name,pa.score,exists(select 1 from public.jo_certificates z where z.registration_id=pr.id) existing,(select z.award from public.jo_certificates z where z.registration_id=pr.id) existing_award,(select z.revoked from public.jo_certificates z where z.registration_id=pr.id) revoked,md5(jsonb_build_array(pr.id,pr.participant_name,c.title,pa.score,award,pa.submitted_at)::text) fingerprint from public.jo_registrations pr join public.jo_attempts pa on pa.registration_id=pr.id where pr.competition_id=c.id and pr.status='approved' and pa.submitted_at is not null order by existing,pr.participant_name,pr.id limit 500
 ) x;
 return jsonb_build_object('competition',c.title,'award',award,'rows',rows,'total',(select count(*) from public.jo_registrations pr join public.jo_attempts pa on pa.registration_id=pr.id where pr.competition_id=c.id and pr.status='approved' and pa.submitted_at is not null));
 elsif p_action<>'issue' then raise exception 'Aksi tidak dikenal';end if;
 rows:=p_payload->'rows';
 if rows is null or jsonb_typeof(rows)<>'array' or jsonb_array_length(rows) not between 1 and 500 then raise exception 'Pilih 1–500 penerima dari pratinjau';end if;
 if (select count(distinct x->>'id') from jsonb_array_elements(rows) x)<>jsonb_array_length(rows) then raise exception 'Penerima ganda atau tidak valid';end if;
 for item in select value from jsonb_array_elements(rows) order by value->>'id' loop
 select * into r from public.jo_registrations where id=(item->>'id')::uuid and competition_id=c.id and status='approved' for update;
 if not found then raise exception 'Penerima bukan peserta aktif kompetisi';end if;
 select * into a from public.jo_attempts where registration_id=r.id and submitted_at is not null;
 if not found then raise exception 'Peserta belum menyelesaikan ujian';end if;
 expected:=md5(jsonb_build_array(r.id,r.participant_name,c.title,a.score,award,a.submitted_at)::text);
 if item->>'fingerprint' is distinct from expected then raise exception 'Data pratinjau berubah. Muat pratinjau ulang';end if;
 insert into public.jo_certificates(registration_id,participant_name,competition_title,award) values(r.id,r.participant_name,c.title,award) on conflict(registration_id) do nothing returning * into cert;
 if found then issued:=issued+1;insert into public.jo_audit(actor,action,entity_id) values(auth.uid(),'certificate_batch_issue',cert.id);else skipped:=skipped+1;end if;
 end loop;
 result:=jsonb_build_object('issued',issued,'skipped',skipped,'batch_id',batch_id,'replayed',false);
 insert into public.jo_certificate_batches(id,actor,competition_id,request_hash,result) values(batch_id,auth.uid(),c.id,request_hash,result);
 return result;
end$$;
revoke all on function public.jo_support(),public.jo_support_admin(jsonb),public.jo_participant_updates(),public.jo_report(uuid),public.jo_certificate_batch(text,jsonb) from public,anon,authenticated;
grant execute on function public.jo_support() to anon,authenticated;
grant execute on function public.jo_support_admin(jsonb),public.jo_participant_updates(),public.jo_report(uuid),public.jo_certificate_batch(text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
