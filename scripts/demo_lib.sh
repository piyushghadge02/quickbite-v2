#!/usr/bin/env bash
# Shared helpers for the QuickBite v2 demo scripts.
# Requires: curl, python3, docker compose. API at $QB_API (default
# http://127.0.0.1:8000), RabbitMQ management at $QB_MGMT
# (default http://127.0.0.1:15672).
set -euo pipefail

QB_API="${QB_API:-http://127.0.0.1:8000}"
QB_MGMT="${QB_MGMT:-http://127.0.0.1:15672}"
MGMT_USER="${RABBITMQ_USER:-guest}"
MGMT_PASS="${RABBITMQ_PASSWORD:-guest}"

jget() { python3 -c "import json,sys; print(json.load(sys.stdin)$1)"; }

qb_login() { # email password -> token on stdout
  curl -s -X POST "$QB_API/api/v1/auth/login" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}" | jget "['access_token']"
}

qb_menu_item() { # token -> "restaurant_id item_id" (first available)
  local rest item
  rest=$(curl -s "$QB_API/api/v1/restaurants" -H "Authorization: Bearer $1" \
    | jget "['items'][0]['id']")
  item=$(curl -s "$QB_API/api/v1/restaurants/$rest/menu" -H "Authorization: Bearer $1" \
    | python3 -c "
import json,sys
items=[m for m in json.load(sys.stdin)['items'] if m['is_available']]
print(items[0]['id'])")
  echo "$rest $item"
}

qb_post_order() { # token restaurant_id item_id [idem-key] -> order_id on stdout
  local key="${4:-$(python3 -c 'import uuid; print(uuid.uuid4())')}"
  curl -s -X POST "$QB_API/api/v1/orders" \
    -H "Authorization: Bearer $1" -H 'Content-Type: application/json' \
    -H "Idempotency-Key: $key" \
    -d "{\"restaurant_id\":\"$2\",\"delivery_address\":\"77 Demo Street, Bengaluru\",\"items\":[{\"menu_item_id\":\"$3\",\"quantity\":1}]}" \
    | jget "['order_id']"
}

qb_order_status() { # token order_id -> status on stdout
  curl -s "$QB_API/api/v1/orders/$2" -H "Authorization: Bearer $1" | jget "['status']"
}

qb_order_history() { # token order_id -> "FROM->TO ..." lines
  curl -s "$QB_API/api/v1/orders/$2/history" -H "Authorization: Bearer $1" \
    | python3 -c "
import json,sys
for h in json.load(sys.stdin):
    print(f\"{h['from_status'] or '(none)'} -> {h['to_status']}  (v{h['version']})  {h['note'] or ''}\")"
}

qb_notifications() { # token order_id -> count on stdout
  curl -s "$QB_API/api/v1/orders/$2/notifications" -H "Authorization: Bearer $1" \
    | jget "['total']"
}

qb_summary() { # admin_token -> compact summary line
  curl -s "$QB_API/api/v1/admin/summary" -H "Authorization: Bearer $1" \
    | python3 -c "
import json,sys
s=json.load(sys.stdin)
print('orders_by_status=%s outbox_pending=%d outbox_scheduled=%d retries_scheduled=%d quarantine=%d'
      % (s['orders_by_status'], s['outbox_pending'], s['outbox_scheduled'],
         s['retries_scheduled'], s['quarantine_total']))"
}

wait_for_status() { # token order_id want timeout_s
  local t=0
  while [ "$t" -lt "$4" ]; do
    local st; st=$(qb_order_status "$1" "$2")
    if [ "$st" = "$3" ]; then echo "$st"; return 0; fi
    sleep 2; t=$((t + 2))
  done
  echo "TIMEOUT (last=$(qb_order_status "$1" "$2"))" >&2; return 1
}

queue_depth() { # queue_name -> messages on stdout (0 if unreachable)
  curl -s -u "$MGMT_USER:$MGMT_PASS" \
    "$QB_MGMT/api/queues/%2F/$1" 2>/dev/null | jget "['messages']" 2>/dev/null || echo 0
}

# Set VAR=VALUE in .env and recreate SERVICE so the new env takes effect.
set_worker_env() { # VAR VALUE SERVICE
  local envf="${ENV_FILE:-.env}"
  [ -f "$envf" ] || { echo "missing $envf (copy .env.example first)" >&2; return 1; }
  if grep -q "^$1=" "$envf"; then
    sed -i "s|^$1=.*|$1=$2|" "$envf"
  else
    printf '%s=%s\n' "$1" "$2" >> "$envf"
  fi
  echo "--- $1=$2 -> recreating $3"
  docker compose up -d "$3" >/dev/null
  sleep 3
}

step() { echo; echo "=== $* ==="; }
