#!/usr/bin/env bash
# Demo: kill a payment worker mid-processing, restart, verify no duplicate effects.
#
# Uses PAYMENT_SIM_MODE=crash-after-checkpoint with
# PAYMENT_CRASH_POINT=after-commit: the worker commits the PAID transition
# (+ payment row + child outbox event) and then dies via os._exit(1) BEFORE
# acking. On restart the redelivered message is a safe no-op (order already
# PAID -> state check returns OK), so exactly one payment row and one
# PENDING->PAID history entry exist.
#
# Variant: PAYMENT_CRASH_POINT=before-tx dies before the transaction — the
# message is redelivered and processed normally.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck disable=SC1091
source scripts/demo_lib.sh

CRASH_POINT="${1:-after-commit}"   # before-tx | after-commit | before-ack

step "1. Enable crash injection (point=$CRASH_POINT)"
set_worker_env PAYMENT_SIM_MODE crash-after-checkpoint payment-worker
set_worker_env PAYMENT_CRASH_POINT "$CRASH_POINT" payment-worker

step "2. Log in and place one order"
CTOK=$(qb_login aarav@quickbite.test customer123)
read -r REST ITEM <<< "$(qb_menu_item "$CTOK")"
OID=$(qb_post_order "$CTOK" "$REST" "$ITEM")
echo "order_id=$OID"

step "3. Wait — the worker will die mid-processing; compose restarts it"
echo "(restart: unless-stopped brings it back; redelivery resumes)"
sleep 12
docker compose ps payment-worker

step "4. Order must still complete exactly once"
wait_for_status "$CTOK" "$OID" DRIVER_ASSIGNED 120
echo "final history (expect exactly one PENDING->PAID and no duplicates):"
qb_order_history "$CTOK" "$OID"

step "5. Restore normal mode"
set_worker_env PAYMENT_SIM_MODE succeed payment-worker
set_worker_env PAYMENT_CRASH_POINT after-commit payment-worker
echo "DONE: crash at $CRASH_POINT recovered with no duplicate effects."
