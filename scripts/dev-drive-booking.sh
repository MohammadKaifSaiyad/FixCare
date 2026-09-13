#!/usr/bin/env bash
# dev-drive-booking.sh — LOCAL TESTING ONLY.
#
# Drives a customer booking through the whole technician-side lifecycle so you can
# watch the customer app advance (Booked → Assigned → Arrived → Diagnosis → Repair
# → Done → Paid). There is no technician app yet, so this simulates the technician
# by calling the real /technician/jobs/* endpoints (plus a couple of unavoidable
# SQL shortcuts noted below).
#
# Prereqs: docker up, backend on :3000 (NODE_ENV=development so OTPs echo devOtp),
# dev DB seeded, and a booking already created from the customer app.
#
# Usage:
#   scripts/dev-drive-booking.sh FC-XXXXXX <stage>
# Stages (each does everything up to and including it):
#   assign      accept the job (Booked → Assigned)
#   enroute     + en-route
#   arrive      + arrive (prints the ARRIVAL CODE for the app's confirm-arrival gate)
#                 NOTE: this does NOT move the booking to ARRIVED — the CUSTOMER does
#                 that by entering the code in the app (or run `confirm-arrival` below).
#   confirm-arrival  customer-side: consume the arrival code → ARRIVED (skips the app)
#   diagnose    + insert 2 diagnosis photos (SQL) + diagnose (→ DIAGNOSED). App shows
#                 the approve/decline card. Customer approves in the app (or run `approve`).
#   approve     customer-side: approve the repair → CUSTOMER_APPROVED (skips the app)
#   repair      + start-repair + insert 3 repair photos (SQL) + complete-repair (→ REPAIR_COMPLETE)
#   pay-cash    customer-side: request the cash receipt OTP (prints devOtp)
#   confirm-cash  technician-side: enter the cash OTP → PAYMENT_RECEIVED (Paid)
#   full        assign → … → REPAIR_COMPLETE, then STOPS. Completion + payment are
#                 two-party OTP handshakes — run pay-cash / confirm-cash (or use the app).
#
# Why some steps are SQL: the photo gate needs a real R2 upload (dev R2 presign URL
# goes nowhere), and the two OTP handshakes are split customer/technician by design.
# Photos are inserted directly; the OTPs are minted via the real endpoints.
set -euo pipefail

B="${BASE_URL:-http://localhost:3000}"
PG="docker exec fixcare-postgres-1 psql -U fixcare -d fixcare_dev -tA"
BOOKING_NUMBER="${1:?usage: dev-drive-booking.sh FC-XXXXXX <stage>  (stages: status assign enroute arrive confirm-arrival diagnose approve repair pay-cash confirm-cash full)}"
# No stage → just print the current state (a safe, common thing to want).
STAGE="${2:-status}"

# jqpy KEY [DEFAULT] — read stdin JSON, print d.get(KEY). Prints DEFAULT (or the raw
# body) when the key is missing / the body isn't an object. Script via -c so stdin
# stays the JSON pipe (a heredoc would steal stdin).
JQPY='
import sys, json
key = sys.argv[1]; default = sys.argv[2] if len(sys.argv) > 2 else ""
raw = sys.stdin.read()
try:
    d = json.loads(raw)
except Exception:
    print(default if default else raw.strip()); sys.exit(0)
if isinstance(d, dict) and key in d and d[key] is not None:
    print(d[key])
else:
    print(default if default else (raw.strip() if not isinstance(d, dict) else json.dumps(d)))
'
jqpy() { python3 -c "$JQPY" "$1" "${2-}"; }

# ── Resolve booking + customer ────────────────────────────────────────────────
BID=$($PG -c "select id from \"Booking\" where \"bookingNumber\"='$BOOKING_NUMBER';")
[ -n "$BID" ] || { echo "booking $BOOKING_NUMBER not found"; exit 1; }
REQ_SKILL=$($PG -c "select s.\"requiredSkill\" from \"Service\" s join \"Booking\" b on b.\"serviceId\"=s.id where b.id='$BID';")
CUST_PHONE=$($PG -c "select u.phone from \"User\" u join \"Customer\" c on c.\"userId\"=u.id join \"Booking\" b on b.\"customerId\"=c.id where b.id='$BID';")
echo "booking=$BOOKING_NUMBER id=$BID skill=$REQ_SKILL customer=$CUST_PHONE"

# ── Log in helper (role CUSTOMER|TECHNICIAN) → prints access token ─────────────
# Tokens are cached under /tmp so repeated stage runs don't burn the OTP send-throttle
# (3 sends / 900s). A cached token is reused if it still authenticates; else re-login.
CACHE_DIR="${TMPDIR:-/tmp}/fixcare-dev-tokens"; mkdir -p "$CACHE_DIR"
login() {
  local phone="$1"
  local role="$2"
  local cache="$CACHE_DIR/$phone.token"
  if [ -f "$cache" ]; then
    local cached; cached=$(cat "$cache")
    # cheap liveness check against a protected route
    if [ "$(curl -s -o /dev/null -w '%{http_code}' "$B/me/profile" -H "authorization: Bearer $cached")" = "200" ]; then
      echo "$cached"; return
    fi
  fi
  local send otp verify token
  send=$(curl -s -X POST "$B/auth/otp/send" -H 'content-type: application/json' -d "{\"phone\":\"$phone\",\"role\":\"$role\"}")
  otp=$(echo "$send" | jqpy devOtp)
  [ -n "$otp" ] || { echo "no devOtp for $phone (throttled? is NODE_ENV=development?) — $send" >&2; exit 1; }
  verify=$(curl -s -X POST "$B/auth/otp/verify" -H 'content-type: application/json' -d "{\"phone\":\"$phone\",\"role\":\"$role\",\"otp\":\"$otp\"}")
  token=$(echo "$verify" | jqpy accessToken)
  [ -n "$token" ] || { echo "login failed for $phone — $verify" >&2; exit 1; }
  echo "$token" > "$cache"; echo "$token"
}

# ── Ensure a VERIFIED technician with the right skill; return its token ────────
# If the booking is already assigned, log in as THAT technician (later transitions
# require the assignee). Otherwise create a fresh VERIFIED tech to accept it.
ensure_tech() {
  local phone token techid assigned
  assigned=$($PG -c "select u.phone from \"User\" u join \"Technician\" t on t.\"userId\"=u.id join \"Booking\" b on b.\"technicianId\"=t.id where b.id='$BID';")
  if [ -n "$assigned" ]; then
    phone="$assigned"
  else
    phone="93${RANDOM}${RANDOM}"; phone="9${phone:0:9}"
  fi
  token=$(login "$phone" TECHNICIAN)
  techid=$($PG -c "select t.id from \"Technician\" t join \"User\" u on u.id=t.\"userId\" where u.phone='$phone';")
  $PG -c "update \"Technician\" set status='VERIFIED', skills='{$REQ_SKILL}' where id='$techid';" >/dev/null
  echo "$token"
}

TAUTH() { echo "authorization: Bearer $TECH_TOKEN"; }
CAUTH() { echo "authorization: Bearer $CUST_TOKEN"; }
tpost() { curl -s -X POST "$B/technician/jobs/$BID/$1" -H "$(TAUTH)" ${2:+-H 'content-type: application/json' -d "$2"}; }
state() { $PG -c "select state from \"Booking\" where id='$BID';"; }

insert_photo() {  # kind
  local kind="$1"
  $PG -c "insert into \"PhotoEvidence\" (id,\"bookingId\",kind,\"r2Key\",\"capturedAt\",\"createdAt\",\"updatedAt\") values (gen_random_uuid(),'$BID','$kind','dev/$BID/$kind.jpg',now(),now(),now());" >/dev/null
  echo "  + photo $kind (SQL)"
}

# ── Stage machine ─────────────────────────────────────────────────────────────
need_tech() { [ -n "${TECH_TOKEN:-}" ] || { echo "logging in a technician…"; TECH_TOKEN=$(ensure_tech); }; }
need_cust() { [ -n "${CUST_TOKEN:-}" ] || { echo "logging in the customer…"; CUST_TOKEN=$(login "$CUST_PHONE" CUSTOMER); }; }

# skip a transition the booking is already past (idempotent re-runs)
past() { # target-state
  local s; s=$(state)
  local order="DISPATCHED ACCEPTED EN_ROUTE ARRIVED DIAGNOSED CUSTOMER_APPROVED REPAIR_IN_PROGRESS REPAIR_COMPLETE PAYMENT_RECEIVED"
  local si ti i=0; for x in $order; do [ "$x" = "$s" ] && si=$i; [ "$x" = "$1" ] && ti=$i; i=$((i+1)); done
  [ "${si:-0}" -ge "${ti:-0}" ]
}
do_assign()  { need_tech; past ACCEPTED && { echo "accept: already $(state)"; return; }; echo "accept → $(tpost accept | jqpy state)"; }
do_enroute() { need_tech; past EN_ROUTE && { echo "en-route: already $(state)"; return; }; echo "en-route → $(tpost en-route | jqpy state)"; }
do_arrive()  { need_tech; local r; r=$(tpost arrive '{"lat":22.24,"lng":73.10}'); ARRIVAL_CODE=$(echo "$r" | jqpy arrivalCode); echo "arrive → ARRIVAL CODE = ${ARRIVAL_CODE:-$r}  (enter it in the app, or run: $0 $BOOKING_NUMBER confirm-arrival)"; }
do_confirm_arrival() { # uses the code from a just-run arrive; else re-mints via arrive
  need_cust
  [ -n "${ARRIVAL_CODE:-}" ] || { do_arrive; }
  echo "confirm-arrival → $(curl -s -X POST "$B/me/bookings/$BID/confirm-arrival" -H "$(CAUTH)" -H 'content-type: application/json' -d "{\"code\":\"$ARRIVAL_CODE\"}" | jqpy state)"
}

case "$STAGE" in
  status)  : ;;  # fall through to the state print at the end
  assign)  do_assign ;;
  enroute) do_assign; do_enroute ;;
  arrive)  do_assign; do_enroute; do_arrive ;;
  confirm-arrival) do_assign; do_enroute; do_arrive; do_confirm_arrival ;;
  diagnose)
    need_tech
    [ "$(state)" = "ARRIVED" ] || { echo "booking is $(state), not ARRIVED — confirm arrival first (enter the code in the app, or run the arrive stage then confirm-arrival)"; exit 1; }
    insert_photo DIAGNOSIS_OVERVIEW; insert_photo DIAGNOSIS_CLOSEUP
    ISSUE=$($PG -c "select di.id from \"DiagnosedIssue\" di join \"ServiceCategory\" c on c.id=di.\"categoryId\" join \"Service\" s on s.\"categoryId\"=c.id join \"Booking\" b on b.\"serviceId\"=s.id where b.id='$BID' and di.\"deletedAt\" is null limit 1;")
    echo "diagnose (issue $ISSUE) → $(tpost diagnose "{\"diagnosedIssueId\":\"$ISSUE\"}" | jqpy state)"
    echo "→ app now shows Approve/Decline. Approve in the app, or run: $0 $BOOKING_NUMBER approve" ;;
  approve)
    need_cust
    echo "approve → $(curl -s -X POST "$B/me/bookings/$BID/approve" -H "$(CAUTH)" | jqpy state)" ;;
  repair)
    need_tech
    [ "$(state)" = "CUSTOMER_APPROVED" ] || { echo "booking is $(state), not CUSTOMER_APPROVED — approve in the app first"; exit 1; }
    echo "start-repair → $(tpost start-repair | jqpy state)"
    insert_photo REPAIR_OLD_PART; insert_photo REPAIR_NEW_PACKAGING; insert_photo REPAIR_INSTALLED
    echo "complete-repair → $(tpost complete-repair | jqpy state)"
    echo "→ REPAIR_COMPLETE. Pay in the app (cash), or run: $0 $BOOKING_NUMBER pay-cash then confirm-cash" ;;
  pay-cash)
    need_cust
    r=$(curl -s -X POST "$B/me/bookings/$BID/pay-cash" -H "$(CAUTH)")
    echo "pay-cash → amount=$(echo "$r" | jqpy amountPaise)  CASH OTP = $(echo "$r" | jqpy devOtp '(none)')  (read to technician, then: $0 $BOOKING_NUMBER confirm-cash <otp>)" ;;
  confirm-cash)
    need_tech
    CODE="${3:?usage: $0 $BOOKING_NUMBER confirm-cash <otp>}"
    echo "confirm-cash → $(tpost confirm-cash "{\"code\":\"$CODE\"}" | jqpy state)" ;;
  full)
    do_assign; do_enroute; do_arrive
    echo "STOP: enter the arrival code in the app (or confirm-arrival), then run diagnose → approve(app) → repair → pay-cash → confirm-cash." ;;
  *) echo "unknown stage: $STAGE"; exit 1 ;;
esac

echo "state now: $(state)"
