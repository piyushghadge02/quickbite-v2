#!/usr/bin/env bash
# Demo: PAYMENT_SIM_MODE=fail-twice-then-succeed
# Expected: order -> PAYMENT attempts 1-2 fail (transient) -> succeeds on
# attempt 3 -> order reaches DRIVER_ASSIGNED. Shows the retry pipeline:
# retry_jobs scheduled, targeted redelivery, admin summary draining.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck disable=SC1091
source scripts/demo_lib.sh

step "1. Switch payment worker to fail-twice-then-succeed"
set_worker_env PAYMENT_SIM_MODE fail-twice-then-succeed payment-worker

step "2. Log in and place one order"
CTOK=$(qb_login aarav@quickbite.test customer123)
ATOK=$(qb_login admin@quickbite.test admin123)
read -r REST ITEM <<< "$(qb_menu_item "$CTOK")"
OID=$(qb_post_order "$CTOK" "$REST" "$ITEM")
echo "order_id=$OID  status=$(qb_order_status "$CTOK" "$OID")"

step "3. Watch the summary while retries fire (~2s + ~10s delays)"
for i in 1 2 3 4 5 6; do
  echo "t+${i}x5s: $(qb_summary "$ATOK")"
  sleep 5
done

step "4. Wait for the order to complete"
wait_for_status "$CTOK" "$OID" DRIVER_ASSIGNED 120
echo "final history:"; qb_order_history "$CTOK" "$OID"
echo "notifications: $(qb_notifications "$CTOK" "$OID")"

step "5. Restore PAYMENT_SIM_MODE=succeed"
set_worker_env PAYMENT_SIM_MODE succeed payment-worker
echo "DONE: order $OID completed after 2 simulated transient failures."
