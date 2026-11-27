# CruDoc and DigiLocker: use cases, rules and gaps

Prepared 27 November 2026. Sources are listed at the end. NeGD can change these rules, so check the current versions on API Setu before submitting.

## 1. All the ways CruDoc could use DigiLocker

"In form" means it is listed in Annexure A of the filled undertaking. The undertaking says later changes need NeGD's prior written approval, so decide the list **before** signing.

| # | Use | How | Verdict |
|---|---|---|---|
| 1 | Fill patient registration (name, DOB, gender, mobile) | Token response and Get User Details | **In form.** Highest value, least data |
| 2 | Match the same patient and avoid duplicates | DigiLocker ID | **In form** (part of 1) |
| 3 | Patient shares lab reports, prescriptions, discharge summaries, vaccination certificates | Lists of issued and uploaded documents, Get File from URI | **In form.** Depends on which issuers publish them; self-uploaded files are unverified |
| 4 | Health insurance or government scheme proof for billing and claims | Issued documents | **In form.** Check each insurer or scheme is an issuer |
| 5 | Age check and guardian consent for under-18 patients | Adult's DOB; child's certificate shared by guardian | **In form.** Relevant to DPDP verifiable parental consent; check whether the healthcare exemption already covers you |
| 6 | Verify doctors (council registration, degree) for CruDoc ID, clinic invites, referrers | Doctor shares own documents | **In form.** NMC has asked colleges to publish degrees; I found nothing confirming Dental Council certificates |
| 7 | Save prescription, bill or summary to the patient's DigiLocker | Upload File (JPG, PNG, PDF, 10 MB) | **In form, later phase.** Lands in "uploaded", not as a verified document |
| 8 | Fetch a document not yet in the locker (e.g. a vaccination certificate) | Pull Document, with DigiLocker's mandatory consent text (shares Aadhaar number, DOB, name with the issuer) | Add only if a specific issuer needs it |
| 9 | Patient address | e-Aadhaar XML or a driving licence | Left out. Ask the patient to type it |
| 10 | Photo ID for medico-legal consent or certificates | PAN or driving licence (`req_doctype`, e.g. `PANCR`, `DRVLC`) | Left out. Add only if a real workflow needs it |
| 11 | Disability, birth or death certificates | Issued documents | Possible under use 3 if health related; name them if you will rely on them |
| 12 | "Sign in with DigiLocker" for doctors or patients (Meri Pehchaan) | OAuth `openid` | Left out. Google sign-in already works |
| 13 | Staff or HR checks (PAN, licence) | Issued documents | Left out. Not needed |
| 14 | Verify a clinic or business (registration, GSTIN, drug licence) | **Entity Locker**, a separate onboarding | Not part of this form |
| 15 | Issue verified prescriptions or certificates | **Issuer** registration, Issuer APIs, Push URI | Not part of this form. Needs separate approval and probably regulatory authority |
| 16 | Exchange health records between providers, ABHA | **ABDM** (NHA sandbox) | Not part of this form. Use ABDM for this |
| 17 | APAAR (student ID) details | Get APAAR Details | Not relevant |

Never do: store Aadhaar numbers, fetch in the background, access records in an emergency without consent, use the data for marketing or AI training, or send DigiLocker documents to the Gemini developer API.

## 2. Technical points (Requester, Meri Pehchaan API v2.4, Sep 2026)

- OAuth 2.0 with PKCE (`S256`). `purpose` and `service_name` are required and shown to the user; letters, digits, spaces and underscores only.
- Useful options: `req_doctype`, `consent_valid_till`, `dl_flow=signup`, `verified_mobile`, `acr` (`aadhaar`, `pan`, `driving_licence`).
- User details: `digilockerid`, `name`, `dob` (DDMMYYYY), `gender`, `eaadhaar` (Y/N). `mobile` comes with the token response.
- Scopes seen in samples: `files.issueddocs`, `files.uploadeddocs`, `userdetails`, `partners.PANCR`, `openid`.
- Sample access token lifetime is 3600 seconds; refresh and revoke APIs exist. Verify the file `hmac`.
- Flow to build: button in registration and Files → Cloud Function (asia-south1) creates the request → patient signs in, ideally **on their own phone** through a link or QR → callback function exchanges the code → review screen → save only confirmed items → log consent → revoke token → log out any shared clinic device.

## 3. Onboarding requirements (Partner SOP dated 5 June 2024)

- Registered Indian entity. Private companies and proprietorships are listed as eligible.
- Functional website describing the online service, and official domain email.
- Entity verification through Entity Locker (nodal officer Aadhaar OTP; CIN, GSTIN, PAN or Udyam).
- Digital signature certificate for API integration.
- Terms of Use signed; use cases and user journey vetted; telephonic meeting.
- No temporary testing access. Demo flow and test data before go-live.
- After go-live: quarterly usage report and **STQC audit report**.
- Unverified accounts are deleted after 3 months; inactive verified accounts are disabled after 3 months.
- DigiLocker FAQ: Indian mobile number and a server located in India.
- Clause 3(iv) mentions authorisation from a regulatory body to issue and authenticate documents. Ask NeGD whether it applies to a requester.

## 4. Check before signing

1. **Company details.** Name, CIN and address are from the Certificate of Incorporation (23 November 2026); a stray comma in "Pandurang, Bhoir Road" was removed. It calls this the mailing address on record, so confirm it is the registered office. Signatory: Director. Attach a board resolution if asked. The company is only days old, and the SOP asks for demonstrable experience in providing online services, so be ready to show it.
2. **Website.** I found no mention of CruDoc on the home, privacy or terms pages. The privacy policy describes only website enquiries. Publish a CruDoc page and a CruDoc privacy policy.
3. **Compliance claim.** Point 1 declares *full* compliance with the IT Act and CERT-In directions (including 6-hour incident reporting and 180-day log retention). The 4 October 2026 audit found security and privacy gaps. Re-check them before signing.
4. **Sub-partners.** If NeGD treats clinics as sub-partners, each needs legal registration, an HTTPS website and domain email, which most small clinics lack. Annexure A asks NeGD to decide.
5. **Storage of documents.** Saving shared documents into patient records must be approved. The undertaking otherwise bars storage beyond approved flows.
6. **India hosting.** The `svayatta-crudoc-dev` database is in `asia-south1`. File storage region and any production project were not checked.
7. **Annexure promises.** Everything in "Data handling" and "Integration flow" must be built as written. DigiLocker is not in the app yet.
8. **NeGD's text** says "We agrees" in point 3. It was left unchanged.

## Sources

- [Partner Organisation Onboarding SOP](https://cf-media.api-setu.in/resources/Partners-SOP.pdf)
- [Requester Meri Pehchaan API Specification v2.4](https://cdn.apisetu.gov.in/portal/assets/Requester-MeriPehchaan-APISpecificationv2.4.pdf)
- [DigiLocker onboarding FAQ](https://www.digilocker.gov.in/assets/FAQ%20DL%20EL_onboarding.pdf)
- [PIB: DigiLocker health records and ABHA](https://www.pib.gov.in/Pressreleaseshare.aspx?PRID=1874894&reg=48&lang=2)
- [DPDP Rules, Rule 10 (secondary copy)](https://dpdpa.com/dpdparules/rule10.html)
- [NMC and DigiLocker certificates (news)](https://news.careers360.com/nmc-asks-medical-colleges-upload-10-year-academic-certificates-degree-marksheet-scorecard-on-digilocker-nad/amp)
