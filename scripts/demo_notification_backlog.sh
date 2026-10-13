#!/usr/bin/env bash
# Demo: notification backlog drain.
#
# Stop the notification worker, place 3 orders (their notification events
# pile up in notification.queue), then restart the worker and watch the
# queue drain: every order ends with its notifications persisted.
# Shows that notification failures never affect order status.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck disable=SC1091
source scripts/demo_lib.sh

step "1. Stop the notification worker"
docker compose stop notification-worker

step "2. Place 3 orders — notifications pile up"
CTOK=$(qb_login aarav@quickbite.test customer123)
read -r REST ITEM <<< "$(qb_menu_item "$CTOK")"
OIDS=()
for i in 1 2 3; do
  OIDS+=("$(qb_post_order "$CTOK" "$REST" "$ITEM")")
done
echo "orders: ${OIDS[*]}"
sleep 15
echo "notification.queue depth: $(queue_depth notification.queue)  (expect > 0)"
for o in "${OIDS[@]}"; do
  echo "  $o status=$(qb_order_status "$CTOK" "$o") notifications=$(qb_notifications "$CTOK" "$o")"
done

step "3. Restart the notification worker — backlog drains"
docker compose start notification-worker
sleep 20
echo "notification.queue depth: $(queue_depth notification.queue)  (expect 0)"
for o in "${OIDS[@]}"; do
  echo "  $o status=$(qb_order_status "$CTOK" "$o") notifications=$(qb_notifications "$CTOK" "$o")"
done
echo "DONE: orders completed while notifications were down; backlog drained on restart."
