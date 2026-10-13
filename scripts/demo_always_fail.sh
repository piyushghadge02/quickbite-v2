#!/usr/bin/env bash
# Demo: PAYMENT_SIM_MODE=always-fail
# Expected: 1 initial attempt + 3 delayed retries exhaust -> order goes
# PENDING -> PAYMENT_FAILED (terminal), order.payment.failed is emitted,
# a quarantine record exists, and a message lands in
# orders.dead-letter.queue (quickbite.dead, key "failed").
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck disable=SC1091
source scripts/demo_lib.sh

step "1. Switch payment worker to always-fail"
set_worker_env PAYMENT_SIM_MODE always-fail payment-worker

step "2. Log in and place one order"
CTOK=$(qb_login aarav@quickbite.test customer123)
ATOK=$(qb_login admin@quickbite.test admin123)
read -r REST ITEM <<< "$(qb_menu_item "$CTOK")"
OID=$(qb_post_order "$CTOK" "$REST" "$ITEM")
echo "order_id=$OID"

step "3. Wait for terminal PAYMENT_FAILED (attempts: 1 + 3 retries ~2/10/30s)"
wait_for_status "$CTOK" "$OID" PAYMENT_FAILED 120
echo "final status: $(qb_order_status "$CTOK" "$OID")"
echo "final history:"; qb_order_history "$CTOK" "$OID"

step "4. Verify quarantine + dead-letter queue"
echo "summary: $(qb_summary "$ATOK")"
echo "orders.dead-letter.queue depth: $(queue_depth orders.dead-letter.queue)"

step "5. Restore PAYMENT_SIM_MODE=succeed"
set_worker_env PAYMENT_SIM_MODE succeed payment-worker
echo "DONE: order $OID ended PAYMENT_FAILED; quarantine_total should be >= 1."
