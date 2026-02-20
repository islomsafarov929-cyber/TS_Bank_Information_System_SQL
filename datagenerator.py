import pyodbc
from faker import Faker
import random
import re
import time
from datetime import datetime, timedelta

# 1. Baza bilan ulanish (autocommit=True tranzaksiya xatolarini oldini oladi)
conn = pyodbc.connect(
    'DRIVER={ODBC Driver 17 for SQL Server};'
    'SERVER=WIN-BSCVJHDJM26;'
    'DATABASE=TZ_BANK;'
    'Trusted_Connection=yes;',
    autocommit=True
)
cursor = conn.cursor()
fake = Faker("uz-UZ")

def clean_phone_number(phone):
    clean_number = re.sub(r'\D', '', phone)
    if not clean_number.startswith('998'):
        clean_number = '998' + clean_number[-9:]
    return clean_number[:12]

# Generate Users
def generate_users(n):
    print(f"Generating {n} users started!")
    for _ in range(n):
        name = fake.name()
        raw_phone = fake.phone_number()
        phone = clean_phone_number(raw_phone)
        email = fake.unique.email()
        
        reg_date = fake.date_time_between(start_date='-2y', end_date='-31d')
        last_active = fake.date_time_between(start_date=reg_date, end_date='now')
        
        status = random.choice(['active', 'blocked', 'inactive'])
        is_vip = 0 
        
        cursor.execute("""
            INSERT INTO users (name, phone_number, email, created_at, last_active_at, status, is_vip, total_balance)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)""", 
            (name, phone, email, reg_date, last_active, status, is_vip, 0))
        
    print("Generating users finished\n")

# Gnerate Cards
def generate_cards():
    cursor.execute("SELECT id FROM users")
    user_ids = [row[0] for row in cursor.fetchall()]
    
    if not user_ids:
        print("No users")
        return

    print(f"Generating cards started")
    for u_id in user_ids:
        num_of_cards = random.randint(1, 2) 
        for _ in range(num_of_cards):
            card_num = fake.unique.credit_card_number(card_type='mastercard')[:16]
            balance = random.randint(100000, 500000000)
            c_type = random.choice(['debit', 'credit', 'savings'])
            is_blocked = 1 if random.random() < 0.1 else 0
            c_created_at = fake.date_time_between(start_date='-1y', end_date='now')

            cursor.execute("""
                INSERT INTO cards (user_id, card_number, balance, is_blocked, created_at, card_type, limit_amount)
                VALUES (?, ?, ?, ?, ?, ?, ?)""", 
                (u_id, card_num, balance, is_blocked, c_created_at, c_type, 150000000))

    print("Generenting cards finished\n")

# Generate Scheduled Payments
def generate_scheduled_payments(n_per_user=1):
    cursor.execute("SELECT id, user_id FROM cards")
    cards_data = cursor.fetchall() 
    
    if not cards_data:
        print("Card not found!")
        return

    print(f"Genereting scheduled payments started")
    for card_id, user_id in cards_data:
        for _ in range(n_per_user):
            amount = random.randint(5000, 500000)
            payment_date = fake.date_time_between(start_date='-10d', end_date='+10d')
            status = random.choice(['pending', 'completed'])
            created_at = payment_date - timedelta(days=random.randint(1, 5))

            cursor.execute("""
                INSERT INTO scheduled_payments (user_id, card_id, amount, payment_date, status, created_at)
                VALUES (?, ?, ?, ?, ?, ?)""", 
                (user_id, card_id, amount, payment_date, status, created_at))
    print("Finished\n")

if __name__ == "__main__":
    try:
        generate_users(1500) 
        generate_cards()   
        generate_scheduled_payments(1) 
        print("Data inserted successfully")
    except Exception as e:
        print(f"Error: {e}")
    finally:
        cursor.close()
        conn.close()