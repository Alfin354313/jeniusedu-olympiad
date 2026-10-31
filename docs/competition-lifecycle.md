# Olympiad competition lifecycle

This branch connects published competitions, registration, manual payment, a single official MCQ exam per competition, released results and manager-issued certificates. The existing red photo banner, login and profile editor remain in place. Not merged or activated in production by the implementation agent.

For the latest bank/recovery/monitoring extension, also read `docs/competition-upgrade.md` and apply its incremental SQL after the original activation below.

## Activate once

1. Back up the target Supabase project and review the SQL. The active public `https://jeniusedu-olympiad.vercel.app/api/auth-config` currently names `https://emcchkpdgwkjovdylcth.supabase.co`, the same project as Panel. Do not move databases or keys. Run `20261028_participant_profiles.sql` if absent, then `20261031_competition_lifecycle.sql`. The companion Panel file `supabase/olympiad_lifecycle.sql` includes both. Migration reruns retain data and do not seed competitions, questions, payments or certificates.
2. The Panel endpoint `/api/olympiad-config` uses public OLYMPIAD_SUPABASE_URL / OLYMPIAD_SUPABASE_ANON_KEY if configured, otherwise reads the Olympiad public config on the server. It rejects service keys. If projects match, reuse the existing manager session. If separated later, a separate Olympiad manager login is required; app_metadata.role must be admin/pengelola/administrator in that project. No service-role key is used.
3. Panel > Olympiad > Peserta & Pembayaran: set the bank, account and account holder. No account number is invented. Paid registration remains disabled on the server until these settings exist.
4. Create a draft competition. Set registration/exam periods and fee. Add 2–8-option text questions with answer key and explanation in Bank Soal Olympiad. Publish through Edit competition or Ujian. Published competitions require at least one question.
5. Use disposable test accounts first: complete profile, register, upload a real test-image proof, approve after checking the bank record, start at the scheduled time, save/submit, publish after end, issue a certificate with the officially decided award. Do not send real funds just for testing.
6. Review the previews and merge the matching Panel/Olympiad PRs only on user instruction. Schema activation and merge are separate operations.

## Behavior

- Public listings have no fabricated competitions. Empty/error states replace sample records.
- Registration snapshots name, level and amount. Retry returns the existing registration. Zero-fee registrations activate immediately; paid ones require proof and manager approval. No payment gateway or automatic bank verification.
- Private proof bucket accepts new JPG/PNG/WebP up to 3 MB under own user/registration paths. Managers view short-lived signed URLs. An uploaded proof alone never enables exam access. Failed proof submissions may leave an unused private image; there is no background cleanup job.
- One immutable attempt snapshot per registration; key/snapshot tables cannot be selected directly by participants. All authoritative timing, access checks, answer validation and grading occur in security-definer RPCs with fixed search paths and explicit auth. Revisions prevent stale overwrites; the UI detects conflicting sessions. Use one device/tab per exam.
- Equal-weight score is 0–100. Deadline closes the attempt on the next server call, including get; publishing results also finalizes remaining attempts. There is no always-running database scheduler. Client polling and server cutoff enforce the deadline on every call.
- Disconnections retain pending answers in the current page and show retry; the latest recovery extension can restore unsent choices after refresh in the same browser, with an explicit user choice. The browser warns before leaving with unsaved answers. No claim of offline persistence or complete cheating prevention. Visibility changes are logged as counts, without automatic penalties.
- Results stay hidden until the manager publishes after the entire competition ends. Each participant sees their own score and dense rank; tied scores share a rank. Other participants' names/answers are not exposed through participant APIs.
- Certificates require approved registration, submitted attempt and released results. The manager chooses the award; the system does not invent medals. Public verification requires an unguessable certificate UUID, returns certificate name/event/award/date, and displays revocation. Browser Print / Save PDF is supported; no digital signature or government accreditation is implied.
- The latest extension reuses the Panel Guru Word/PDF/image importer and adds separate image editors for MCQ authoring. Multi-round qualification, capacity quotas, refunds and custom medal rules are not automated.

## Verification evidence and limits

PGlite tests: rerunnable schema, missing-role/participant admin denial, private tables/proofs, registration retry, manual approval, schedule gate, attempt identity, immutable question editing, grading/release, own rank/certificate, free activation and deadline finalization. jsdom: catalogue/registration, HTML escaping, live KPIs, schedule gating, profile preservation, admin list/editor/question routing, exam rules/start/queued save/submit and hidden key/score before release. These are local fixtures; they are not production login, real payment, load testing or live Storage proof verification. Browser preview uses mock data only; no production data was written.
