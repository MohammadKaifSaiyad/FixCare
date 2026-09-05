# FixCare Customer App — Auth Screens Visual Spec (Splash, Phone Entry, OTP Entry, Home)

**Date:** 2026-09-05 · **Source of truth:** `Claude Design/fixcare-customer-app-design/project/FixCare Customer App.dc.html`
(static HTML mockup, artboards A1–A4 and C1). This is a **visual spec for Flutter reproduction** —
no app code. Frame size in the mockup is **360×760 dp** (phone device chrome shown as a rounded
bezel around each artboard — not part of the app UI itself). Font throughout: **Outfit** (Google
Font, weights 300/400/500/600/700). All colors are exact hex values pulled from the mockup's inline
styles.

---

## Global design language (applies to all four screens)

- **Font family:** `Outfit` everywhere, falling back to `system-ui, sans-serif`. No other typeface
  appears anywhere in the file.
- **Corner-radius system:** buttons/CTAs = 16px · text field containers = 14px · larger cards
  (booking summary, address cards) = 16–18px · small chips/badges = 5–6px · pills (status badges,
  filter chip) = 999px (fully round) · logo mark container = 14–28px depending on size · device
  bezel (chrome, not app) = 38px.
- **Spacing rhythm:** screen side padding is consistently **20px** (phone entry/name step uses
  20px with slightly more top padding at 28–32px). Vertical gaps between stacked field groups are
  **12–20px**; gap from a heading block to the first input is **~26px**; a status bar occupies the
  top **~10px 18px 4px** padding band before content starts. Primary CTA button is always **56px**
  tall and pinned to the bottom of the scroll area (content column uses `flex:1` spacer above it).
- **Status bar (mockup chrome, replicate loosely):** time "9:41" left, signal/battery glyphs right,
  12px, weight 500, color `#241A15`, in a `10px 18px 4px` padding band. This is decorative
  (represents the OS status bar) — do not hard-code "9:41" in the real app; leave the space for the
  system status bar instead.
- **Bottom home-indicator bar (mockup chrome):** a 22px-tall band centered with a 112×4px pill in
  `#D8C9C0` — this represents the Android/iOS gesture bar, not an app element. Omit in Flutter
  (system nav handles this) or, if reproducing pixel-for-pixel against the mock, treat as non-
  interactive decoration only.

---

## 1. Splash Screen (A1 · Splash / token gate)

**Logic (not visual, but relevant to build):** "has token? → Home : Phone entry" — the splash is a
token-gate/loading screen, not a static brand-only splash.

### Layout (top to bottom, centered)
Full-bleed colored background, content **vertically and horizontally centered** as a column with
**20px gap** between children:
1. Logo mark (88×88px rounded-square, white background, wrench+badge icon inside)
2. Wordmark lockup (small icon + "FixCare" text), horizontal, **9px gap**, centered
3. Tagline text ("Sahi kaam, sahi daam.")
4. Progress/loading indicator bar, **28px margin-top** from the tagline

No app bar, no scroll — this is a single fixed full-screen composition.

### Colors
- **Background:** `#C2521B` (primary terracotta) — fills the entire screen.
- **Logo mark container:** `#fff` (white square, rounded).
- **Wordmark text:** `#fff` (white).
- **Tagline text:** `#FBDCCB` (a light, warm pink-tan tint of the primary).
- **Loading track:** `rgba(255,255,255,0.28)` (translucent white).
- **Loading fill (progress):** `#fff` (solid white).

### Typography
| Element | Weight | Size | Color |
|---|---|---|---|
| Wordmark "FixCare" | 700 | 32px | `#fff`, letter-spacing -0.01em |
| Tagline "Sahi kaam, sahi daam." | 400 | 15px | `#FBDCCB` |

### Components
- **Logo mark container:** 88×88px, `border-radius: 28px`, background `#fff`, centered flex,
  drop shadow `0 6px 18px rgba(36,26,21,.18)`. Contains the SVG logo mark at 52×52px (see Logo
  section below), drawn in its **primary-colored variant** (wrench in `#C2521B`, badge circle in
  `#1D6B4F`).
- **Wordmark row icon:** the same SVG logo mark rendered smaller (26×26px) in its **white
  variant** (wrench drawn in `#fff` instead of `#C2521B`, badge stays `#1D6B4F`) — used inline next
  to the wordmark text since it now sits on the terracotta background rather than inside the white
  square.
- **Loading indicator:** a fixed-position (not necessarily animated in the static mock) progress
  bar: track 120×4px, `border-radius:2px`, background translucent white; fill is a 52×4px solid
  white bar positioned at the start — in the real app this should be an indeterminate or
  determinate loading indicator (token check is fast, so a brief indeterminate spinner/bar is
  appropriate), not a literal frozen 52px fill.

### Interaction/state notes
- This is purely a transient loading state — no buttons, no text input, no error state depicted.
- The only "state" is implicit: token present → navigate to Home; no token → navigate to Phone
  entry. No visual branching shown for this in the mockup (single artboard).

---

## 2. Phone Entry Screen (A2 · Phone entry)

**Endpoint (context only):** `POST /auth/otp/send { phone }`

### Layout (top to bottom)
No back button, no app bar title — this is the entry point. Column, left-aligned, padding
`32px 20px 20px` (top 32px, sides 20px, bottom 20px), gap 8px between primary elements, `flex:1`
spacer before the CTA:
1. Small brand mark badge (52×52px), `margin-bottom: 20px`
2. Heading: "Enter your mobile number"
3. Subtext: "We'll send a 6-digit code to verify it." (`margin-top: 6px`)
4. Phone input field (`margin-top: 26px`) — country code + divider + number, with a text caret
   shown mid-entry
5. Helper text: "Indian 10-digit mobile only" (`margin-top: 10px`)
6. *(flexible spacer fills remaining height)*
7. Primary CTA button: "Send code" (56px tall)
8. Legal microcopy: "By continuing you agree to FixCare's Terms and Privacy Policy." (`margin-top:
   14px`, centered)

### Colors
- **Screen background:** `#FBF7F4` (off-white/cream — this is the standard app background, distinct
  from the terracotta splash).
- **Brand badge background:** `#FDECE2` (very light terracotta tint).
- **Brand badge glyph/text:** `#C2521B`.
- **Heading text:** `#241A15` (primary text — inherited from body).
- **Subtext / helper text:** `#7A6A62` (muted/secondary text).
- **Phone field background:** `#fff`.
- **Phone field border (focused/active state shown):** `1.5px solid #C2521B`.
- **Phone field divider (between +91 and number):** `#EADFD8`.
- **Phone field text ("+91" and digits):** `#241A15`.
- **Primary button fill:** `#C2521B`.
- **Primary button text:** `#fff`.
- **Legal microcopy text:** `#8B7A71`.

### Typography
| Element | Weight | Size | Color |
|---|---|---|---|
| Brand badge "F" | 600 | 26px | `#C2521B` |
| Heading "Enter your mobile number" | 600 | 28px | `#241A15`, letter-spacing -0.02em, line-height 1.2 |
| Subtext | 400 | 14.5px | `#7A6A62`, line-height 1.5 |
| Phone field "+91" | 500 | 19px | `#241A15` |
| Phone field digits | 600 | 22px | `#241A15`, letter-spacing 1.5px |
| Helper text | 400 | 13px | `#7A6A62` |
| Button "Send code" | 600 | 17px | `#fff` |
| Legal microcopy | 400 | 12.5px | `#8B7A71`, line-height 1.5, centered |

### Components
- **Brand badge:** 52×52px, `border-radius:16px`, background `#FDECE2`, centered "F" glyph in
  `#C2521B` (600/26px). (This is a placeholder monogram tile, not the full SVG logo — simpler
  in-app icon tile.)
- **Phone number field:** height **60px**, `border-radius:14px`, background `#fff`, border
  `1.5px solid #C2521B` (this is the field's normal/active appearance in the mock — treat as the
  standard focused/filled state; an unfocused empty state should likely use the muted border color
  `#EADFD8` at `1.5px`, consistent with other text fields elsewhere in the file — **not explicitly
  shown for this field**, inferred from pattern). Internal layout: horizontal flex, `gap:10px`,
  padding `0 14px`. Contents: "+91" prefix text, a 1×26px vertical divider line (`#EADFD8`), then
  the entered digits with a visible text caret (rendered as `|` at 28% opacity to simulate a
  blinking cursor).
- **Primary button ("Send code"):** height 56px, `border-radius:16px` (not pill — a rounded
  rectangle), fill `#C2521B`, centered white text 600/17px. Full width of content column.
- No secondary/text button on this screen.

### Interaction/state notes
- The field is shown mid-input (partially filled: "98250 41" + caret) — implies live-formatted
  grouping of the 10-digit number (visual grouping "98250 41" suggests a 5+2 or similar chunking as
  the user types, though the final format isn't fully shown since not all digits are entered).
- No error state is depicted on this screen in the file (error states appear on the OTP screen
  instead — see A4 below). No disabled-button state is shown either; by convention (matching A4's
  disabled pattern) a disabled "Send code" button should use fill `#EFE1D8` / text `#B09B90`.

---

## 3. OTP Entry Screen

Two artboards cover this: **A3 (default/entering state)** and **A4 (error + throttled state)**.
Both share the same layout skeleton; A4 shows the error/disabled variants.

**Endpoint (context only):** `POST /auth/otp/verify` · 401 wrong code · 429 resend throttle.

### Layout (top to bottom, A3 baseline)
1. Status bar band (see Global notes)
2. App bar row: back arrow (44×44px tappable circle) + title "Verify number", height 56px,
   padding `8px 16px`, gap 14px
3. Content column, padding `16px 20px 20px`, gap 6px:
   - Line: "Code sent to **+91 98250 41xxx**" (masked number, last digits hidden)
   - 6-box OTP input row (`margin-top:24px`, gap 10px between boxes)
   - *(A3 only)* Dev-OTP hint banner (`margin-top:18px`)
   - *(A4 only)* Inline error line below the OTP row (`margin-top:12px`)
   - *(A4 only)* "Too many requests" card (`margin-top:22px`)
   - Resend row: "Resend in 00:24" (left) / "Resend code" link (right), `margin-top:18px`,
     space-between
   - *(flexible spacer)*
   - Primary CTA: "Verify & continue" (56px)

### Colors — A3 (normal / mid-entry state)
- **Screen background:** `#FBF7F4`.
- **Back arrow icon:** `#241A15`.
- **Title text:** `#241A15`.
- **"Code sent to" line:** `#5C4B43`, with the phone number itself bolded in `#241A15`.
- **OTP box (empty/filled, non-focused):** background `#fff`, border `1.5px solid #EADFD8`,
  digit text `#241A15` (default box shown filled with digit, weight 600, size 24px).
- **OTP box (focused/active — the box being typed into):** border `1.5px solid #C2521B`, digit
  text color `#C2521B` (the 5th box in the mock, holding "7", is the active one).
- **OTP box (empty, not yet reached):** background `#fff`, border `1.5px dashed #D8C9C0` (the 6th,
  untouched box).
- **Dev-OTP hint banner background:** `#FFF6E8`, border `1px solid #F0DDBC`.
- **Dev-OTP hint text:** `#6B5320`, with the code value bolded (600 weight).
- **Resend countdown text ("Resend in 00:24"):** `#7A6A62`.
- **Resend link (disabled/countdown-active state, i.e. not yet tappable):** `#C1B0A7` (muted —
  visually disabled since a countdown is active), weight 600.
- **Primary button (enabled):** fill `#C2521B`, text `#fff`.

### Colors — A4 (error + throttled state)
- **OTP boxes (all 6, error state):** background `#FEF1EE` (pale red/pink tint), border
  `1.5px solid #C9442B` (error red), digit text `#A63116` (dark red-orange).
- **Inline error line:** icon `⚠` + text "That code isn't right. 2 tries left.", color `#A63116`,
  weight 500, size 13.5px.
- **"Too many requests" card:** background `#fff`, border `1px solid #EADFD8`, `border-radius:14px`,
  padding 16px. Title "Too many requests" (600/14px, `#241A15` default text color), body text
  "You've asked for a few codes in a row. Try again in 4 minutes, or check your SMS inbox."
  (`#7A6A62`, 13.5px, line-height 1.5).
- **Primary button (disabled, throttled state):** fill `#EFE1D8` (muted warm neutral), text
  `#B09B90` (muted) — visually disabled/non-interactive.

### Typography (shared across A3/A4 unless noted)
| Element | Weight | Size | Color |
|---|---|---|---|
| App bar title "Verify number" | 600 | 18px | `#241A15` |
| Back arrow glyph | 400 | 22px | `#241A15` |
| "Code sent to" body | 400 | 15px | `#5C4B43`, line-height 1.5 (phone number segment: weight 600, `#241A15`) |
| OTP digit | 600 | 24px | context-dependent (see colors above) |
| Dev-OTP hint | 400 | 13px | `#6B5320` (code value: weight 600) |
| Resend countdown / link | 600 | 14px | `#7A6A62` (countdown) / `#C1B0A7` (disabled link) |
| Error inline text | 500 | 13.5px | `#A63116` |
| Throttle card title | 600 | 14px | `#241A15` |
| Throttle card body | 400 | 13.5px | `#7A6A62`, line-height 1.5 |
| Button text | 600 | 17px | `#fff` (enabled) / `#B09B90` (disabled) |

### Components
- **Back button:** 44×44px circular tap target, `border-radius:22px`, transparent background,
  centered "←" glyph at 22px.
- **OTP box:** 6 equal-width boxes in a flex row (`flex:1` each, `gap:10px` between), each
  **62px tall**, `border-radius:14px`, centered digit text. Border/fill/text color vary by state
  (empty/filled/focused/error) as documented above. The dashed-border style (`1.5px dashed
  #D8C9C0`) specifically marks an untouched/pending box in the normal flow.
- **Dev-OTP hint banner:** `border-radius:12px`, background `#FFF6E8`, border `1px solid #F0DDBC`,
  padding `12px 14px`, horizontal flex with a 🛠 emoji icon (15px) + text, gap 10px. This is a
  **dev/test-build-only element** — must be conditionally rendered only in non-production builds,
  never shown to real users (matches the "Dev vs prod" note in the backend context doc — devOtp is
  only returned in dev/test).
- **Resend row:** space-between flex row; left side is muted countdown text, right side is the
  "Resend code" action — shown disabled/muted while the countdown (00:24) is active, and would
  presumably become the active-link color (`#C2521B`, matching the global link style `a {
  color:#C2521B }`) once the countdown reaches zero (not explicitly shown as a separate state in
  the file, but inferable from the global `a` style in the doc's `<style>` block).
- **Primary button "Verify & continue":** same 56px/16px-radius pattern as other screens; disabled
  variant (A4, throttled) swaps fill to `#EFE1D8` and text to `#B09B90`.

### Interaction/state notes
- **Error state (401 wrong code):** all 6 OTP boxes turn red-tinted (fill `#FEF1EE`, border
  `#C9442B`, text `#A63116`) and an inline warning line appears below with a live tries-remaining
  count ("2 tries left").
- **Throttled state (429):** an additional card appears below the error line explaining the
  cooldown ("Try again in 4 minutes..."), and the primary CTA becomes visually disabled.
- **Dev-only hint:** the `devOtp` hint box is a build-time/environment-gated element, not a
  permanent production UI piece.
- **Masking:** the phone number is shown partially masked ("+91 98250 41xxx") — last 3 digits
  hidden, consistent with the project's PII-masking convention (though a phone number is not on
  the Aadhaar-masking list, this appears to be a deliberate lighter-touch masking for the
  confirmation string).

---

## 4. Home Screen (C1 · Home — category grid)

**Endpoint (context only):** `GET /catalog/categories`. Only the **shell/chrome** and stub content
are in scope here — the rich catalog grid is documented for completeness but is a later slice.

### Layout (top to bottom)
1. Status bar band
2. Header row (`padding:12px 20px 16px`, space-between, align-items: flex-start):
   - Left: small label "SERVICE AT" (uppercase eyebrow) above "Home · Padra ▾" (address switcher)
   - Right: circular avatar chip with initials
3. Content column (`padding:0 20px`, gap 18px, scrollable/flex:1):
   - Search bar (placeholder only, non-functional stub state)
   - **Active booking card** (dark card — only shown when a booking is in progress; this is
     conditional content, not always present)
   - "What needs fixing?" section heading
   - 2×2 category grid (4 tiles shown; catalog content — later slice, but shell shows the grid
     pattern)
4. Bottom tab bar (fixed, 3 tabs: Home / Bookings / Account)

### Colors
- **Screen background:** `#FBF7F4`.
- **Eyebrow label "SERVICE AT":** `#7A6A62`, weight 500.
- **Address switcher text "Home · Padra":** `#241A15`, weight 600, with a small `▾` chevron in
  `#7A6A62`.
- **Avatar chip background:** `#FDECE2`, text "RP" in `#C2521B` (weight 600).
- **Search bar:** background `#fff`, border `1px solid #EADFD8`, `border-radius:14px`, height 52px;
  placeholder icon `⌕` and text both `#9A8A81`.
- **Active booking card background:** `#241A15` (dark, near-black-brown — the one dark surface in
  the whole light-theme app), `border-radius:18px`, padding `16px 18px`.
  - Eyebrow "IN PROGRESS · FC-2841": `#F6C7AE` (light peach), weight 600, letter-spacing .06em.
  - Status pill "EN ROUTE": text `#241A15` on background `#F6C7AE`, pill-shaped (999px), weight
    600, 11px.
  - Title "Refrigerator not cooling": `#fff`, weight 600, 17px.
  - Subtext "Mahesh S. is on the way · today 12:00–14:00": `#C9B7AE`, 13.5px.
  - CTA "Track booking": fill `#C2521B`, text `#fff`, height 44px, `border-radius:12px`.
- **Section heading "What needs fixing?":** `#241A15`, weight 600, 18px.
- **Category tile:** background `#fff`, border `1px solid #EADFD8`, `border-radius:16px`, padding
  16px, min-height 104px. Icon swatch 40×40px, `border-radius:12px`, background varies per
  category (tinted per icon: Refrigerator `#FDECE2`, AC `#E7F0F6`, Washing machine `#EDEBF7`,
  Water purifier `#E9F5EF`) with an emoji glyph at 19px. Tile label: `#241A15`, weight 600, 15px.
- **Bottom tab bar:** background `#fff`, top border `1px solid #EADFD8`, padding `8px 0 10px`.
  Active tab (Home): icon+label both `#C2521B` (icon 19px, label weight 600, 11.5px). Inactive
  tabs (Bookings, Account): icon+label both `#8B7A71`, label weight 500.

### Typography
| Element | Weight | Size | Color |
|---|---|---|---|
| Eyebrow "SERVICE AT" | 500 | 12.5px | `#7A6A62` |
| Address switcher | 600 | 16px | `#241A15` |
| Avatar initials | 600 | 15px | `#C2521B` |
| Search placeholder | 400 | 15px | `#9A8A81` |
| Booking card eyebrow | 600 | 11.5px | `#F6C7AE`, letter-spacing .06em |
| Booking card status pill | 600 | 11px | `#241A15` (on `#F6C7AE` bg) |
| Booking card title | 600 | 17px | `#fff` |
| Booking card subtext | 400 | 13.5px | `#C9B7AE` |
| Booking card CTA | 600 | 15px | `#fff` |
| Section heading | 600 | 18px | `#241A15` |
| Category tile label | 600 | 15px | `#241A15` |
| Tab label (active) | 600 | 11.5px | `#C2521B` |
| Tab label (inactive) | 500 | 11.5px | `#8B7A71` |

### Components
- **Address switcher:** plain text row, not a bordered button in the mock — tappable area implied
  by the trailing chevron; no visible container/border.
- **Avatar chip:** 42×42px circle, `border-radius:21px`, background `#FDECE2`, centered 2-letter
  initials in `#C2521B`.
- **Search bar (stub):** non-functional placeholder-only state shown — height 52px, icon + grey
  placeholder text, no active/focused variant depicted on this screen.
- **Active booking card:** the one high-contrast dark surface in the app — reserved specifically
  for "you have something in progress" state. This should be **conditionally rendered** (absent
  when the customer has no active booking) — for a bare logged-in stub with no bookings yet, omit
  this card entirely and let the category grid sit higher.
- **Category grid tile:** 2-column CSS grid, 12px gutter, each tile min-height 104px, icon swatch
  top-left, label below.
- **Bottom tab bar:** 3 equal-flex columns, each a centered icon+label stack (gap 3px). Uses glyph
  characters in the mock (⌂ home, ☰ bookings, ☺ account) — in Flutter use real icon assets/Material
  icons of equivalent meaning (house, list, person), not literal glyph characters.

### Interaction/state notes
- The address switcher (chevron) implies a tap target to change/select address — behavior not
  detailed beyond the visual affordance.
- The active-booking card is explicitly conditional content tied to booking state (`EN ROUTE` badge
  suggests it mirrors whatever booking-state enum drives the tracking screen) — for a logged-in
  **stub** Home (per this task's scope — "just the shell + what a logged-in stub should show"),
  render the header, search bar, "What needs fixing?" heading, category grid, and tab bar; treat
  the active-booking card and full catalog grid contents as later-slice/conditional, not required
  for the initial stub.
- No error/empty/loading state for Home is depicted in the mockup (single artboard, happy-path
  populated state only).

---

## The FixCare Logo (SVG monogram + wordmark)

Drawn twice in the file at different sizes/color variants (splash screen, 52px and 26px versions);
identical geometry both times, viewBox `0 0 48 48`.

### Description
A **wrench-and-check-badge monogram**:
- A stylized **wrench silhouette** occupies the upper-left ~2/3 of the mark — a single closed path
  describing a wrench head/handle shape (path data: `M30.5 8.5a8 8 0 0 0-10.2 9.9L8.8 29.9a3.2 3.2
  0 0 0 0 4.5l.8.8a3.2 3.2 0 0 0 4.5 0l11.5-11.5A8 8 0 0 0 35.5 13l-4.2 4.2-3.5-.9-.9-3.5 4.2-4.2a8
  8 0 0 0-.6-.1Z`), filled solid (no stroke).
- A **circular badge** sits at the bottom-right, centered at `(34, 34)` with radius `10` — overlaps
  the wrench's lower-right end, giving a "tool + verification stamp" composition.
- Inside the badge, a **checkmark stroke** (`M29.5 34.2l3 3 6-6.4`), drawn as a white stroke, round
  linecap/linejoin, stroke-width 2.6 — a simple two-segment tick mark.

### Color variants
| Variant | Wrench fill | Badge fill | Check stroke | Used where |
|---|---|---|---|---|
| Primary-on-white | `#C2521B` | `#1D6B4F` | `#fff` | Inside the white 88px splash badge |
| White-on-color | `#fff` | `#1D6B4F` | `#fff` | Inline next to the wordmark on the terracotta splash background |

The badge circle (`#1D6B4F`, the success green) and its white checkmark **never change color** —
only the wrench switches between primary terracotta and white depending on background. This means
the green "verified/check" badge is a fixed brand element (reads as "verified technician /
trustworthy repair" — consistent with the product's trust-score positioning), while the wrench
recolors for contrast.

### Proportions
- Overall mark drawn in a 48×48 viewBox; rendered at 52×52px (large, inside the white splash
  square) and 26×26px (small, inline with wordmark text).
- Wrench occupies roughly the top-left 60% of the frame; the check-badge circle (diameter 20,
  i.e. ~42% of the 48px frame) is anchored to the bottom-right corner, overlapping the wrench's
  terminus.
- Wordmark "FixCare" is set in Outfit 700 (bold), 32px, `#fff`, letter-spacing -0.01em, placed
  immediately to the right of the small (26px) mark with a 9px gap — this icon+wordmark pairing is
  the standard horizontal lockup for use on colored/dark backgrounds. The larger standalone mark
  (52px, in the white rounded square) is the app-icon-style lockup, used without the wordmark.

---

## Design language summary (see also the top-of-conversation report)

Palette roles: `#C2521B` primary/terracotta (CTAs, active states, brand), `#1D6B4F` success green
(fixed to the logo's check badge and "serviceable" affirmations), `#FBF7F4` app background,
`#241A15` primary text (and the one dark surface, the active-booking card), `#7A6A62` / `#5C4B43`
muted text tiers, `#EADFD8` / `#D8C9C0` neutral borders/dividers. Typography is a single-family
(Outfit) scale from 12px helper text to 34px display, weighted 500/600 for emphasis and 400 for
body. Corner radii step from 999px (pills) → 16–18px (cards/buttons) → 12–14px (fields/chips) →
5–6px (small tags). Spacing follows a 20px screen-margin baseline with 8–12px micro-gaps and
18–26px section gaps, every primary CTA fixed at 56px height pinned to the bottom safe area.

---

## Could not determine from the file

- **Unfocused/empty state of the phone-number field** (A2) — only the mid-entry/active-border
  state is shown; the resting (unfocused, no border-highlight) appearance is inferred by pattern
  from other fields in the file (`1.5px solid #EADFD8`), not directly observed for this specific
  field.
- **"Resend code" active/enabled visual state** (A3/A4) — only the disabled/countdown-muted color
  (`#C1B0A7`) is shown; the enabled/tappable color is inferred from the file's global `a { color:
  #C2521B }` link style, not shown directly on this element.
- **Splash loading indicator behavior** — the mock shows a static 52px-filled 120px track; whether
  this should be an indeterminate spinner, a determinate progress bar, or a shimmer animation in
  the real app is a build-time decision the static HTML can't convey.
- **Home screen empty/no-active-booking layout spacing** — the mockup only shows the state *with*
  an active booking card present; exact vertical rhythm when that card is absent (e.g., does the
  "What needs fixing?" heading move up by the card's full height + gap, or is there additional
  top-of-list spacing) is not directly shown.
- **Exact phone-number live-formatting/grouping pattern** — the field shows "98250 41" with a caret
  mid-string; the precise grouping rule for all 10 digits (e.g., 5-5, 5-3-2) isn't fully
  demonstrated since the mock freezes mid-entry.
- **Any dark-mode / theme variant** — the mockup is a single fixed light theme; no dark-theme
  tokens are defined anywhere in the file.
