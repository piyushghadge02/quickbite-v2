#!/usr/bin/env python3
"""Seed QuickBite v2 with fictional demo data. Idempotent — safe to re-run.

Creates:
  * admin account   admin@quickbite.test / admin123        (role: admin)
  * customers       aarav@quickbite.test / customer123
                    diya@quickbite.test  / customer123     (role: customer)
  * 3 restaurants with menus (prices in INR minor units; item_biryani=1250
    and item_lassi=400 match the assignment's worked checkout example)
  * 3 drivers

Usage:
    cd ~/workspace/quickbite-build/quickbite-v2
    .venv/bin/python scripts/seed.py

All data is fictional. Passwords are bcrypt-hashed at seed time; no real
credentials are stored anywhere.
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from sqlalchemy import select  # noqa: E402

from backend.app.database import SessionLocal  # noqa: E402
from backend.app.models import Driver, MenuItem, Restaurant, User  # noqa: E402
from backend.app.security import hash_password  # noqa: E402

USERS = [
    dict(id="user_admin", email="admin@quickbite.test", name="Asha Admin",
         role="admin", password="admin123"),
    dict(id="user_aarav", email="aarav@quickbite.test", name="Aarav Sharma",
         role="customer", password="customer123"),
    dict(id="user_diya", email="diya@quickbite.test", name="Diya Patel",
         role="customer", password="customer123"),
]

RESTAURANTS = [
    dict(
        id="rest_spice",
        name="Spice Symphony",
        address="12 Lake Road, Bengaluru",
        image_url="https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=400&h=300&fit=crop",
        cuisine="North Indian",
        description="Authentic North Indian flavors with a modern twist. Famous for our slow-cooked biryanis and tandoori specialties.",
        rating=4.5,
        delivery_time_minutes=35,
    ),
    dict(
        id="rest_dragon",
        name="Dragon Wok",
        address="44 MG Road, Bengaluru",
        image_url="https://images.unsplash.com/photo-1526318896980-cf78c088247c?w=400&h=300&fit=crop",
        cuisine="Chinese",
        description="Wok-tossed Chinese classics made fresh to order. From schezwan noodles to dim sum, every dish packs a punch.",
        rating=4.3,
        delivery_time_minutes=25,
    ),
    dict(
        id="rest_crust",
        name="Crust & Co.",
        address="7 Park Street, Bengaluru",
        image_url="https://images.unsplash.com/photo-1565299624946-b28f40a0ca4b?w=400&h=300&fit=crop",
        cuisine="Italian",
        description="Wood-fired pizzas with artisanal toppings and hand-stretched dough. Also serving fresh pastas and antipasti.",
        rating=4.6,
        delivery_time_minutes=30,
    ),
    dict(
        id="rest_saffron",
        name="Saffron Trail",
        address="88 Brigade Road, Bengaluru",
        image_url="https://images.unsplash.com/photo-1601050690597-df0568f70950?w=400&h=300&fit=crop",
        cuisine="Mughlai",
        description="Royal Mughlai cuisine with rich gravies and aromatic kebabs. A culinary journey through India's royal kitchens.",
        rating=4.4,
        delivery_time_minutes=40,
    ),
    dict(
        id="rest_tokyo",
        name="Tokyo Bites",
        address="23 Koramangala, Bengaluru",
        image_url="https://images.unsplash.com/photo-1579027989536-b7b1f875659b?w=400&h=300&fit=crop",
        cuisine="Japanese",
        description="Fresh sushi, sashimi, and ramen bowls crafted by trained chefs. Authentic flavors from the streets of Tokyo.",
        rating=4.7,
        delivery_time_minutes=35,
    ),
    dict(
        id="rest_mexico",
        name="Casa Mexicana",
        address="15 Indiranagar, Bengaluru",
        image_url="https://images.unsplash.com/photo-1551504326-3a8e5d0e8c1f?w=400&h=300&fit=crop",
        cuisine="Mexican",
        description="Vibrant Mexican street food — tacos, burritos, quesadillas with house-made salsas and fresh guacamole.",
        rating=4.2,
        delivery_time_minutes=28,
    ),
    dict(
        id="rest_green",
        name="Green Bowl",
        address="32 Whitefield, Bengaluru",
        image_url="https://images.unsplash.com/photo-1512621776951-a57141f2eefd?w=400&h=300&fit=crop",
        cuisine="Healthy / Salads",
        description="Nutrient-packed bowls, fresh salads, cold-pressed juices, and guilt-free desserts. Eat clean, feel great.",
        rating=4.5,
        delivery_time_minutes=20,
    ),
    dict(
        id="rest_burger",
        name="Burger Junction",
        address="55 HSR Layout, Bengaluru",
        image_url="https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=400&h=300&fit=crop",
        cuisine="American / Burgers",
        description="Gourmet burgers with 100% Angus beef, brioche buns, and signature sauces. Loaded fries and thick shakes too.",
        rating=4.3,
        delivery_time_minutes=25,
    ),
    dict(
        id="rest_thai",
        name="Thai Orchid",
        address="18 Jayanagar, Bengaluru",
        image_url="https://images.unsplash.com/photo-1559314809-0d155014e29e?w=400&h=300&fit=crop",
        cuisine="Thai",
        description="Authentic Thai curries, stir-fries, and noodle dishes. Balanced sweet, sour, salty, and spicy in every bite.",
        rating=4.4,
        delivery_time_minutes=30,
    ),
    dict(
        id="rest_dosa",
        name="Dosa Plaza",
        address="41 Malleshwaram, Bengaluru",
        image_url="https://images.unsplash.com/photo-1630383698234-2d6b6f8b6c3e?w=400&h=300&fit=crop",
        cuisine="South Indian",
        description="Crispy dosas, fluffy idlis, and filter coffee. 50+ dosa varieties from classic masala to creative fusion.",
        rating=4.6,
        delivery_time_minutes=22,
    ),
    dict(
        id="rest_kebab",
        name="Kebab Kingdom",
        address="67 Electronic City, Bengaluru",
        image_url="https://images.unsplash.com/photo-1544025162-d76694265947?w=400&h=300&fit=crop",
        cuisine="Kebabs / Grills",
        description="Succulent kebabs marinated overnight and grilled to perfection. Served with roomali roti and mint chutney.",
        rating=4.5,
        delivery_time_minutes=35,
    ),
]

# (id, restaurant_id, name, price_minor, is_available)
MENU = [
    # Spice Symphony - North Indian
    ("item_biryani", "rest_spice", "Chicken Biryani", 12500, True),
    ("item_lassi", "rest_spice", "Mango Lassi", 400, True),
    ("item_curry", "rest_spice", "Paneer Butter Masala", 18000, True),
    ("item_naan", "rest_spice", "Butter Naan (2 pc)", 600, True),
    ("item_tikka", "rest_spice", "Chicken Tikka", 14000, True),
    ("item_dal", "rest_spice", "Dal Makhani", 8000, True),
    ("item_kebab", "rest_spice", "Seekh Kebab", 12000, True),

    # Dragon Wok - Chinese
    ("item_noodles", "rest_dragon", "Hakka Noodles", 14000, True),
    ("item_manchuria", "rest_dragon", "Veg Manchuria", 16000, True),
    ("item_soup", "rest_dragon", "Hot & Sour Soup", 9000, True),
    ("item_friedrice", "rest_dragon", "Schezwan Fried Rice", 13000, True),
    ("item_dumplings", "rest_dragon", "Steamed Dumplings (6 pc)", 11000, True),
    ("item_chilli_paneer", "rest_dragon", "Chilli Paneer", 15000, True),

    # Crust & Co. - Italian
    ("item_margherita", "rest_crust", "Margherita Pizza", 22000, True),
    ("item_farmhouse", "rest_crust", "Farmhouse Pizza", 28000, True),
    ("item_garlicbread", "rest_crust", "Garlic Breadsticks", 11000, True),
    ("item_pepperoni", "rest_crust", "Pepperoni Pizza", 26000, True),
    ("item_pasta", "rest_crust", "Penne Arrabbiata", 18000, True),
    ("item_tiramisu", "rest_crust", "Tiramisu", 9000, True),

    # Saffron Trail - Mughlai
    ("item_nihari", "rest_saffron", "Nihari Gosht", 18000, True),
    ("item_kebab_platter", "rest_saffron", "Kebab Platter", 22000, True),
    ("item_biryani_mughlai", "rest_saffron", "Mutton Biryani", 16000, True),
    ("item_sheermal", "rest_saffron", "Sheermal (2 pc)", 800, True),
    ("item_korma", "rest_saffron", "Chicken Korma", 15000, True),

    # Tokyo Bites - Japanese
    ("item_sushi", "rest_tokyo", "Salmon Sushi (8 pc)", 18000, True),
    ("item_ramen", "rest_tokyo", "Tonkotsu Ramen", 16000, True),
    ("item_tempura", "rest_tokyo", "Tempura Platter", 14000, True),
    ("item_gyoza", "rest_tokyo", "Chicken Gyoza (6 pc)", 12000, True),
    ("item_mochi", "rest_tokyo", "Mochi Ice Cream (3 pc)", 8000, True),

    # Casa Mexicana - Mexican
    ("item_tacos", "rest_mexico", "Chicken Tacos (3 pc)", 14000, True),
    ("item_burrito", "rest_mexico", "Beef Burrito Bowl", 16000, True),
    ("item_quesadilla", "rest_mexico", "Cheese Quesadilla", 12000, True),
    ("item_nachos", "rest_mexico", "Loaded Nachos", 13000, True),
    ("item_churros", "rest_mexico", "Churros with Chocolate", 9000, True),

    # Green Bowl - Healthy
    ("item_buddha", "rest_green", "Buddha Bowl", 15000, True),
    ("item_quinoa", "rest_green", "Quinoa Salad", 13000, True),
    ("item_smoothie", "rest_green", "Green Smoothie", 8000, True),
    ("item_wrap", "rest_green", "Hummus Veggie Wrap", 11000, True),
    ("item_energy", "rest_green", "Energy Balls (4 pc)", 6000, True),

    # Burger Junction - American
    ("item_classic_burger", "rest_burger", "Classic Cheeseburger", 14000, True),
    ("item_bacon_burger", "rest_burger", "Bacon BBQ Burger", 18000, True),
    ("item_veggie_burger", "rest_burger", "Veggie Burger", 13000, True),
    ("item_fries", "rest_burger", "Loaded Fries", 9000, True),
    ("item_shake", "rest_burger", "Chocolate Shake", 8000, True),

    # Thai Orchid - Thai
    ("item_pad_thai", "rest_thai", "Pad Thai Noodles", 14000, True),
    ("item_green_curry", "rest_thai", "Green Curry with Rice", 16000, True),
    ("item_tom_yum", "rest_thai", "Tom Yum Soup", 11000, True),
    ("item_massaman", "rest_thai", "Massaman Curry", 17000, True),
    ("item_sticky_rice", "rest_thai", "Mango Sticky Rice", 9000, True),

    # Dosa Plaza - South Indian
    ("item_masala_dosa", "rest_dosa", "Masala Dosa", 8000, True),
    ("item_mysore_dosa", "rest_dosa", "Mysore Masala Dosa", 10000, True),
    ("item_rava_dosa", "rest_dosa", "Rava Dosa", 11000, True),
    ("item_idli", "rest_dosa", "Idli Sambar (4 pc)", 7000, True),
    ("item_filter_coffee", "rest_dosa", "Filter Coffee", 1500, True),

    # Kebab Kingdom - Kebabs
    ("item_chicken_kebab", "rest_kebab", "Chicken Shish Kebab", 13000, True),
    ("item_lamb_kebab", "rest_kebab", "Lamb Seekh Kebab", 16000, True),
    ("item_paneer_kebab", "rest_kebab", "Paneer Tikka Kebab", 12000, True),
    ("item_roomali", "rest_kebab", "Roomali Roti (2 pc)", 800, True),
    ("item_biryani_kebab", "rest_kebab", "Kebab Biryani", 15000, True),
]

DRIVERS = [
    dict(id="driver_1", name="Ravi Kumar", phone="+91-90000-00001"),
    dict(id="driver_2", name="Sana Sheikh", phone="+91-90000-00002"),
    dict(id="driver_3", name="Vikram Rao", phone="+91-90000-00003"),
]


def main() -> None:
    session = SessionLocal()
    try:
        for u in USERS:
            if session.get(User, u["id"]) is None:
                session.add(User(
                    id=u["id"], email=u["email"], name=u["name"], role=u["role"],
                    password_hash=hash_password(u["password"]),
                ))
        for r in RESTAURANTS:
            existing = session.get(Restaurant, r["id"])
            if existing is None:
                session.add(Restaurant(
                    id=r["id"],
                    name=r["name"],
                    address=r["address"],
                    is_active=True,
                    image_url=r.get("image_url"),
                    cuisine=r.get("cuisine"),
                    description=r.get("description"),
                    rating=r.get("rating"),
                    delivery_time_minutes=r.get("delivery_time_minutes"),
                ))
            else:
                # Update existing restaurant with new fields
                existing.image_url = r.get("image_url", existing.image_url)
                existing.cuisine = r.get("cuisine", existing.cuisine)
                existing.description = r.get("description", existing.description)
                existing.rating = r.get("rating", existing.rating)
                existing.delivery_time_minutes = r.get("delivery_time_minutes", existing.delivery_time_minutes)
        for mid, rid, name, price, avail in MENU:
            if session.get(MenuItem, mid) is None:
                session.add(MenuItem(id=mid, restaurant_id=rid, name=name,
                                     price_minor=price, currency="INR",
                                     is_available=avail))
        for d in DRIVERS:
            if session.get(Driver, d["id"]) is None:
                session.add(Driver(id=d["id"], name=d["name"], phone=d["phone"],
                                   is_active=True))
        session.commit()
        counts = {
            "users": session.execute(select(User)).scalars(),
        }
        print("seed complete: users=%d restaurants=%d menu_items=%d drivers=%d" % (
            len(list(counts["users"])),
            session.query(Restaurant).count(),
            session.query(MenuItem).count(),
            session.query(Driver).count(),
        ))
        print("logins: admin@quickbite.test/admin123, "
              "aarav@quickbite.test/customer123, diya@quickbite.test/customer123")
    finally:
        session.close()


if __name__ == "__main__":
    main()
