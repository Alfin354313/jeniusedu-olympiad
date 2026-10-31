# Bank Soal, recovery, rules, monitoring and CSV upgrade

## Activation

The original lifecycle SQL already activated by the user remains the prerequisite. Run the new `20261101_bank_recovery_monitor.sql` after it on the same Supabase project. The identical Panel script is `supabase/olympiad_bank_recovery_monitor.sql`. This is an incremental, rerunnable migration: old registrations, payments, answers, scores and certificates are retained. Existing submitted attempts are not regraded; existing attempts receive the original 1/0/0 scoring snapshot. Do not rerun the old lifecycle script after this upgrade, because it replaces RPC definitions with the old versions. For a new project, apply profiles → lifecycle → this upgrade.

No production SQL, bank transaction or user data write was performed by the implementation agent. Preview branches remain unmerged.

## Bank Soal

Panel Guru's shared Word/PDF parser and review dialog are reused via an Olympiad adapter; teacher and Tryout permissions retain their existing behavior. The adapter can identify the authenticated Olympiad manager independently of Panel's user. Only unpublished competitions without attempts can receive questions. Word `.docx` inline PNG/JPG/WebP images are preserved, including the existing composite-choice correction/detection tools. PDF imports text only; scanned PDFs, OCR, PDF images and special equation conversion are not added.

Import is A–D/E MCQ, max 100 questions / 4 MB per batch, max 200 questions / 8 MB per competition. Each question is capped at 1 MB; fields permit up to three allowlisted images, each up to 128 KiB encoded source. Server validation rejects invalid image tokens. Atomic batches, stable retry IDs and exact-content duplicate detection prevent ordinary retries from adding duplicates. Invalid rows roll back the batch. Question snapshots remain immutable and private until released.

Manual question editing supports 2–8 choices with separate media editors for prompt, each choice and explanation. Admin Detail and participant exam/review both render image tokens without executing HTML. Existing text-only questions and existing snapshots remain compatible.

## Recovery

Unsent choices are stored in the browser under user + competition + attempt. No question text, images, answer keys or auth tokens are cached in this draft. On reload, the server session is fetched first. The participant explicitly chooses Restore Local Answers or Use Server Answers; already-accepted matching answers are removed from the draft without duplicate writes. The draft cannot transfer to another account or attempt. Saved/submitted answers remain authoritative on the server; restored choices still require a successful server save before submission.

When connectivity returns, the current page retries its queue. Conflicting sessions require reload/reconciliation, not blind overwrite. Submitted drafts are deleted; account sign-out clears that user's drafts. Entries older than 24 hours are discarded. Storage-blocked/private-browser cases display a warning and continue server saves. Recovery is limited to the same browser/origin/device; clearing browser data removes it. The server deadline remains authoritative, and late offline answers are not accepted.

## Rules and results

Manager settings add points for correct/wrong/blank answers and written exam/award rules. Default stays 1/0/0; configurable correct points are positive, wrong/blank points non-positive. Score = raw points / maximum possible points × 100, rounded to 2 decimals and clamped to 0–100. The policy is copied into the attempt when started and cannot be changed through management APIs once attempts exist. Public cards and the start screen display rules. Equal scores share a dense rank; no hidden time tiebreaker or automatic medal allocation. Certificates remain a manager decision following the published award rules.

## Monitoring and exports

Admin-only `jo_monitor` returns progress counts, server time, deadline, last successful save/contact and page departures, without full questions, answer keys or raw answers. It also finalizes expired attempts using their frozen scoring policy. UI polls every 15 seconds while the exam menu is visible, uses server-relative time for its countdown, and stops on navigation. Last contact is not presented as proof of online/offline status; visibility logs are not automatically penalized.

CSV exports cover registrations, approved non-zero payments and results/ranks/certificate status. They contain no proof signed URLs, question keys or raw answers. UTF-8 BOM, proper quoting and formula-neutralized cells support Excel safely. Before result release, admin result exports explicitly label results as unpublished.

## Verification

PGlite tests exercise both migrations twice, batch retry/content dedup and tamper rejection, unsafe media rejection, image snapshot/key release, frozen penalty scoring, monitor role/progress/privacy, plus previous registration/payment/certificate cases. jsdom tests cover reload recovery, explicit restore/discard, ambiguous responses, account/attempt isolation, cleanup, queued saves, polling races, media editor preservation, real shared import dialog with separate manager identity, monitor timers, stale navigation, and CSV injection handling. Four existing teacher parser regressions also pass against the modified shared importer.

A live browser Word/PDF upload attempt could not be completed because the browser transport disconnected. No live Supabase/Storage import, actual financial transfer, load test or broad production security audit is claimed. Existing DOCX reader and PDF engine are reused, but this turn's document-to-database coverage uses local parser/DOM and SQL fixtures rather than a signed-in browser.
