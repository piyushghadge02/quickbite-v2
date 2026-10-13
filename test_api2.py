import urllib.request, json

# Login
data = json.dumps({'email': 'aarav@quickbite.test', 'password': 'customer123'}).encode()
req = urllib.request.Request('http://localhost:8000/api/v1/auth/login', data=data, headers={'Content-Type': 'application/json'})
resp = urllib.request.urlopen(req, timeout=5)
token = json.loads(resp.read())['access_token']
print('Token:', token[:20])

# Get restaurants
req = urllib.request.Request('http://localhost:8000/api/v1/restaurants', headers={'Authorization': 'Bearer ' + token})
resp = urllib.request.urlopen(req, timeout=5)
data = json.loads(resp.read())
for r in data['items']:
    print(f"{r['id']}: {r['name']} - {r.get('cuisine')} - {r.get('rating')} - {r.get('delivery_time_minutes')}")
print('Total:', data['total'])