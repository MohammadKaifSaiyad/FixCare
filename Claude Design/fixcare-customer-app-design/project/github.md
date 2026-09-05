repo: MohammadKaifSaiyad/FixCare
branch: main

## Last sync
date: 2026-09-04T15:10:00Z

### Updated in this project
- Designed the FixCare customer app screen set (auth, onboarding, catalog, booking, tracking, payment, dispute) from the uploaded screen-context brief.
- Picked a visual direction: terracotta #C2521B primary, warm off-white surfaces, Outfit + Noto Sans Gujarati, Material 3 geometry — `docs/01-overview/naming-and-branding.md` left this open.
- Added a customer-side state gallery covering every BookingDto state, plus dark-theme variants.

## Screen map
| Project screen | Repo source |
|---|---|
| A · Auth & session (A1–A4) | docs/designs/2026-05-31-auth-module-design.md, docs/plans/2026-06-01-auth-otp-registration.md |
| B · First run: name & address | docs/designs/2026-06-03-profile-update-slice-design.md, docs/designs/2026-06-06-addresses-module-design.md |
| C · Discovery & booking | docs/designs/2026-06-04-service-catalog-design.md, docs/designs/2026-06-07-booking-b1-creation-design.md |
| D · Tracking & handshakes | docs/designs/2026-06-13-booking-b2a-dispatch-design.md, 2026-06-13-booking-b3-arrival-design.md, 2026-06-14-booking-b4a-diagnosis-design.md, 2026-07-11-booking-b4b-photos-design.md, 2026-07-12-booking-b5-completion-design.md |
| E · Payment, receipt & dispute | docs/designs/2026-07-18-booking-b6a-upi-payment-design.md, 2026-07-19-booking-b6b-cash-design.md, 2026-07-26-booking-b7-disputes-design.md |
| F · State machine gallery | docs/02-product/core-flow.md |
| G · Dark theme | docs/01-overview/naming-and-branding.md (visual direction was open) |

Note: `apps/customer` is an empty Flutter scaffold — these screens are the design ahead of that build, not a recreation of existing UI.
