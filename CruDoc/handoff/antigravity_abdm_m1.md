# CruDoc: ABDM Milestone 1, screen check

Updated 2026-11-27. This file is the whole brief: you need no other context.

## ▶ DO NOW

Do **Task 19**, run the **Checks**, then **stop at GATE 4** and report.

## Done already (do not redo)

Tasks 1 to 17 are built and reviewed: ABHA create and verify, Scan and Share, and the review fixes. Do not change server code.

## Rules

- Repo: `C:\Soham\Kamachya_Goshti\Svayatta_CruDoc`. All paths below start at `CruDoc\`.
- `main` has many uncommitted changes. **Never** run `git commit`, `stash`, `checkout`, `restore`, `reset` or `clean`.
- Do not deploy, set secrets or call ABDM. No new packages.
- UI: follow `.claude\rules\crudoc-ui.md`. Design tokens only, minimal forms, no explanatory subtext.
- Made-up names and numbers are allowed **only inside the test file**.
- Run `flutter test` one command at a time.

## Task 19. Render the screens to pictures and fix what looks wrong

The app cannot be clicked through here, so draw the screens from a widget test. Copy the approach in `test/tool/island_render_test.dart` (theme, fonts, saving PNGs).

1. In `lib/features/abdm/data/abdm_api.dart` only, make `static AbdmApi instance` replaceable (drop `final`, mark `@visibleForTesting` use in a comment). In the test, replace it with a fake that returns fixed replies, or pass a fake `CallableClient`.
2. New `test/tool/abdm_render_test.dart`. Save to `build/abdm_render/` at **1280×800** and **390×844**, driving the dialog by typing and tapping:
   - "Has ABHA" empty; invalid entry; no ABHA for a mobile.
   - Profile list with two profiles, one selected.
   - OTP choice; OTP step with countdown; no resends left.
   - "Create ABHA" with consent; communication-mobile OTP.
   - Address step with suggestions, a failing rule, and "ABHA address already exists."
   - Result step.
   - The "already linked" comparison dialog.
   - Patient header with "Add ABHA" and with a saved number.
   - Add-patient dialog after "Fill from ABHA" (locked fields).
   - Counter QR screen: with a facility, and without. If the PDF preview cannot render in a test, say so.
3. Open every PNG and look at it. Fix overflow, clipped text, cramped or uneven spacing, wrong tokens, more than one filled button in a region, and anything unreadable on the phone size. Render again after fixing.

## Checks

1. `flutter test test/tool/abdm_render_test.dart`, then `flutter test test/features/abdm`.
2. `flutter analyze` on files you touched: no new issues.

## GATE 4: stop and report

List the PNG paths, what you fixed on each, anything you could not render, and each Check's real output.

## Owner steps (not for Antigravity)

1. Finish sandbox registration at https://sbxai.abdm.gov.in; get the client ID and secret, and a facility ID in the Health Facility Registry linked to it.
2. `firebase functions:secrets:set` for `ABDM_CLIENT_ID`, `ABDM_CLIENT_SECRET`, `ABDM_CALLBACK_KEY` (long random string). Until all exist, every functions deploy fails.
3. Deploy; allow public access (`--no-invoker-iam-check`) on `abdm` and `abdmCallback`.
4. Run `functions/scripts/abdm-facility.js` and `abdm-set-bridge.js`. Add Firestore TTL policies on `abdmFlows.expiresAt` and `abdmShares.expiresAt`.
5. Test every case in the [official list](https://docs.abdm.gov.in/docs/hiecm/v3/resources/test-cases/m1) on the sandbox.
6. Ask NHA: callback token verification, production hosts, whether Scan and Share is required, and whether M1 can exit alone (the registration form says each milestone is its own exit request; the docs say there is no per-milestone submission).
7. Go live: functional testing, NHA review, security audit, GSTIN, undertaking, demo. [Details](https://docs.abdm.gov.in/docs/hiecm/v3/getting-started/going-live).

## Known limit (not to be fixed now)

A scanned patient without a birth day or month shows age 0.
