import urllib.request, json, uuid

# Login
data = json.dumps({'email': 'aarav@quickbite.test', 'password': 'customer123'}).encode()
req = urllib.request.Request('http://localhost:8000/api/v1/auth/login', data=data, headers={'Content-Type': 'application/json'})
resp = urllib.request.urlopen(req, timeout=5)
token = json.loads(resp.read())['access_token']
print('Login successful')

# Get restaurants
req = urllib.request.Request('http://localhost:8000/api/v1/restaurants', headers={'Authorization': 'Bearer ' + token})
resp = urllib.request.urlopen(req, timeout=5)
data = json.loads(resp.read())
print(f'Got {data["total"]} restaurants')
for r in data['items'][:3]:
    print(f'  - {r["name"]}: {r.get("cuisine")}, {r.get("rating")} stars, {r.get("delivery_time_minutes")}min')

# Get menu for first restaurant
restaurant_id = data['items'][0]['id']
req = urllib.request.Request(f'http://localhost:8000/api/v1/restaurants/{restaurant_id}/menu', headers={'Authorization': 'Bearer ' + token})
resp = urllib.request.urlopen(req, timeout=5)
menu = json.loads(resp.read())
print(f'Got {menu["total"]} menu items for {data["items"][0]["name"]}')

# Test checkout
checkout_data = {
    'restaurant_id': restaurant_id,
    'delivery_address': '123 Test Street, Bengaluru 560001',
    'items': [{'menu_item_id': menu['items'][0]['id'], 'quantity': 2}]
}
idem_key = str(uuid.uuid4())
req = urllib.request.Request('http://localhost:8000/api/v1/orders', 
    data=json.dumps(checkout_data).encode(),
    headers={'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json', 'Idempotency-Key': idem_key})
resp = urllib.request.urlopen(req, timeout=10)
order = json.loads(resp.read())
print(f'Order placed: {order["order_id"]}, status: {order["status"]}')

# Get order history
req = urllib.request.Request('http://localhost:8000/api/v1/orders', headers={'Authorization': 'Bearer ' + token})
resp = urllib.request.urlopen(req, timeout=5)
orders = json.loads(resp.read())
print(f'Order history: {orders["total"]} orders')

print('\nAll API endpoints working correctly!')