#!/usr/bin/env bash
# Demo: broker-stop outbox recovery.
#
# With RabbitMQ stopped, POST /orders still returns 202: the acceptance
# transaction commits order + outbox row to PostgreSQL; the outbox
# dispatcher cannot publish, so the row stays "pending". Restart the
# broker and the dispatcher publishes it — the order then flows to
# DRIVER_ASSIGNED. Proves the API never loses events on broker outage.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck disable=SC1091
source scripts/demo_lib.sh

step "1. Sanity: pipeline healthy"
CTOK=$(qb_login aarav@quickbite.test customer123)
ATOK=$(qb_login admin@quickbite.test admin123)
echo "readiness: $(curl -s "$QB_API/health/ready" | jget "['status']")"

step "2. Stop the broker (keep postgres + api + workers running)"
docker compose stop rabbitmq
sleep 5
echo "readiness now: $(curl -s "$QB_API/health/ready" | jget "['status']")  (expect not_ready)"

step "3. Place an order with the broker DOWN — must still be accepted (202)"
read -r REST ITEM <<< "$(qb_menu_item "$CTOK")"
OID=$(qb_post_order "$CTOK" "$REST" "$ITEM")
echo "order_id=$OID  status=$(qb_order_status "$CTOK" "$OID")  (expect PENDING)"
echo "summary: $(qb_summary "$ATOK")  (expect outbox_pending >= 1)"

step "4. Restart the broker"
docker compose start rabbitmq
sleep 8

step "5. The pending outbox row is published; the order must complete"
wait_for_status "$CTOK" "$OID" DRIVER_ASSIGNED 120
echo "summary: $(qb_summary "$ATOK")  (expect outbox_pending = 0)"
echo "DONE: no event lost while the broker was down."
