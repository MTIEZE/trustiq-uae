# Who may do what

Three lists and one flag decide everything in this system, and until now none of
them was written down in the same place. This file is that place, and the last
section of it is checked by `supabase/tests/schema.test.sql` against the real
database, so it cannot quietly stop being true.

## The roles

There is no `role` column anywhere. Membership is a fact about a row, which
means it cannot be forged by a client sending a different string.

| Role | How somebody becomes one | Where it lives |
| --- | --- | --- |
| **Signed out** | The default. Holds the publishable key and nothing else. May add an address to the beta list and read nothing back. | `anon` |
| **Signed in, unverified** | Created an account. | `authenticated`, `profiles.identity_verified_at is null` |
| **Waiting** | Asked to be verified and has not been answered. | `app.verification_requests.state = 'pending'` |
| **Refused** | Was answered no, with a reason they can act on. | `app.verification_requests.state = 'rejected'` |
| **Verified** | A person looked and said so. | `profiles.identity_verified_at is not null` |
| **Reviewer** | Added by hand, in SQL. Takes over escalated disputes. | `app.reviewers` |
| **Operator** | Added by hand, in SQL. Reads the platform's numbers. | `app.admins` |
| **System** | Not a person. Timers, the model pipeline, the schedulers. | no `auth.uid()`, service role |

Reviewer and operator are deliberately separate lists. One decides somebody's
case; the other watches the business. The same person is both today, and merging
them would mean that adding somebody to a dashboard also hands them live
disputes.

There is no "in progress" verification flag on the profile: a profile is
verified or it is not, and the queue holds everything in between. Two facts, two
places, so a request can be refused and re-made without the profile ever having
been half-verified.

## What each one may do

| Action | Who | Where the rule is |
| --- | --- | --- |
| Join the beta list | **anybody, signed out** | insert policy on `beta_signups`, no read for anyone |
| Draft a contract, send an invitation | anybody signed in | RLS on `transactions` |
| Make a contract binding | both parties verified | `0003_transactions.sql`, on the `accept` event |
| Set how long a contract runs | its author, while it is a draft | `transactions_update_own_draft` |
| File evidence | a party | RLS on `evidence`, role derived from the session |
| Open a dispute | a party, from `active` or `delivered` only | `app.transaction_transitions` |
| Ask the model for a resolution | a verified party, from `open` only | `may_request_resolution` |
| Accept or refuse a proposal | a party, and it takes both to end it | `app.dispute_transitions` |
| Take over an escalated dispute | a reviewer | `app.is_reviewer` |
| Read the platform's numbers | an operator | `app.is_admin` |
| Open somebody's file, or suspend an account | an operator, and it is logged | `app.note_admin_access` writes a row first |
| Read who looked at whom | nobody through the API | service role, `app.admin_access_log` is append-only |
| Verify somebody, or withdraw it | nobody through the API | service role, `scripts/verifications.mjs` |
| Expire, renew, warn | nobody through the API | service role, the daily schedule |

An operator can now see personal data, which 0020 deliberately prevented. The
rule was not abandoned, it was paid for: every read of a person's record writes
a row saying who looked and at whom, that log is append-only, and **an operator
cannot read it**. An audit trail the audited can read is a list of what to avoid
next time.

Two things are true of every row and worth saying once. The actor is always
derived from `auth.uid()` and never accepted as an argument, so "act as the
other party" is not a request anybody can make. And every rule above is enforced
in the database, so a screen that shows the wrong thing is a bug in the screen
and not a way in.

## Every function, and who may call it

Generated from the database and checked against it. `system only` means no
client role holds EXECUTE and the caller must be the service role.

**Nothing here is ever callable by `anon`.** The publishable key ships inside
the app, so anything it can reach is a public endpoint whether or not it was
meant to be one. That is asserted twice: in the schema tests, and daily against
production by `scripts/run-schedule.mjs`, because the tests only ever see a
database built from `supabase/migrations` and production is not only that.

| Function | Callable by |
| --- | --- |
| `accept_milestone(p_milestone_id uuid)` | signed in |
| `accept_resolution_proposal(p_proposal_id uuid)` | signed in |
| `admin_access_history(p_days integer)` | system only |
| `admin_activity(p_limit integer)` | signed in |
| `admin_ai_quality()` | signed in |
| `admin_beta_waiting()` | signed in |
| `admin_daily(p_days integer)` | signed in |
| `admin_disputes()` | signed in |
| `admin_overview()` | signed in |
| `admin_people(p_query text, p_limit integer)` | signed in |
| `admin_person(p_user_id uuid)` | signed in |
| `admin_reports(p_state text)` | signed in |
| `admin_resolve_report(p_report_id uuid, p_outcome text, p_note text)` | signed in |
| `admin_set_suspended(p_user_id uuid, p_suspended boolean, p_reason text)` | signed in |
| `admin_verification_pending()` | signed in |
| `admin_verification_queue()` | signed in |
| `apply_dispute_event(p_dispute_id uuid, p_event dispute_event)` | signed in |
| `apply_transaction_event(p_transaction_id uuid, p_event transaction_event)` | signed in |
| `beta_list()` | system only |
| `block_person(p_user_id uuid)` | signed in |
| `claim_dispute(p_dispute_id uuid)` | signed in |
| `claim_invitation(p_code text)` | signed in |
| `client_reachable_functions()` | system only |
| `close_account(p_user_id uuid)` | system only |
| `decide_verification(p_request_id uuid, p_approve boolean, p_note text)` | system only |
| `deliver_milestone(p_milestone_id uuid)` | signed in |
| `expire_overdue_contracts()` | system only |
| `find_counterparty(p_email text)` | signed in |
| `invite_counterparty(p_email text, p_invitee_is party_role, p_description text, p_terms text, p_total_amount_fils bigint)` | signed in |
| `issue_ai_proposal(p_dispute_id uuid, p_decision resolution_decision, p_summary text, p_disputed_amount_fils bigint, p_seller_amount_fils bigint, p_buyer_amount_fils bigint, p_confidence numeric, p_model_id text, p_issued_at timestamp with time zone, p_findings jsonb, p_ai_call_id bigint)` | system only |
| `issue_human_resolution(p_dispute_id uuid, p_decision resolution_decision, p_summary text, p_seller_amount_fils bigint, p_buyer_amount_fils bigint, p_findings jsonb)` | signed in |
| `mark_notifications_read(p_before timestamp with time zone)` | signed in |
| `mark_notifications_sent(p_ids bigint[], p_error text)` | system only |
| `may_request_resolution(p_dispute_id uuid)` | signed in |
| `my_blocks()` | signed in |
| `my_invitations()` | signed in |
| `my_notifications(p_limit integer)` | signed in |
| `my_reports()` | signed in |
| `my_verification()` | signed in |
| `notifications_to_send(p_grace interval)` | system only |
| `record_activity()` | signed in |
| `record_manual_verification(p_user_id uuid, p_note text)` | system only |
| `renew_due_contracts()` | system only |
| `report_content(p_kind text, p_subject_id uuid, p_reason text, p_detail text)` | signed in |
| `request_milestone_revision(p_milestone_id uuid)` | signed in |
| `request_verification(p_legal_name text, p_document_kind text, p_how text)` | signed in |
| `revoke_invitation(p_id uuid)` | signed in |
| `revoke_verification(p_user_id uuid, p_note text)` | system only |
| `set_preferred_locale(p_locale text)` | signed in |
| `unblock_person(p_user_id uuid)` | signed in |
| `verification_queue()` | system only |
| `withdraw_verification_request()` | signed in |
| `write_deadline_notices(p_accept_within interval, p_period_within interval)` | system only |
