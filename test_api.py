import httpx
import asyncio

async def test():
    async with httpx.AsyncClient() as client:
        # Login
        resp = await client.post('http://localhost:8000/api/v1/auth/login', json={'email': 'aarav@quickbite.test', 'password': 'customer123'})
        token = resp.json()['access_token']
        print('Token:', token[:20])
        
        # Get restaurants
        headers = {'Authorization': f'Bearer {token}'}
        resp = await client.get('http://localhost:8000/api/v1/restaurants', headers=headers)
        data = resp.json()
        for r in data['items']:
            print(f"{r['id']}: {r['name']} - {r.get('cuisine')} - {r.get('rating')} - {r.get('delivery_time_minutes')}")
        print('Total:', data['total'])

asyncio.run(test())