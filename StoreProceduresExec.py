import pyodbc
import time
import random

conn = pyodbc.connect(
    'DRIVER={ODBC Driver 17 for SQL Server};'
    'SERVER=WIN-BSCVJHDJM26;'
    'DATABASE=TZ_BANK;'
    'Trusted_Connection=yes;', autocommit=True
)
cursor = conn.cursor()

def get_active_cards():
    cursor.execute("SELECT id, user_id FROM cards WHERE is_blocked = 0")
    return cursor.fetchall()

# sp_MakeTransfer 
def simulate_transfers(total_count=500):
    cards = get_active_cards()
    if len(cards) < 2: return
    print(f"Generating {total_count} transfers started")
    
    success_count = 0
    for i in range(total_count):
        c1, c2 = random.sample(cards, 2)
        amount = random.randint(1000, 500000)
        try:
            cursor.execute("{CALL sp_MakeTransfer (?, ?, ?)}", (c1.id, c2.id, amount))
            success_count += 1
            if i % 50 == 0: conn.commit() 
        except:
            continue
        time.sleep(3)
    conn.commit()
    print(f"  OK: {success_count} transfers have done.")

# sp_AtmOperation
def simulate_atm(total_count=200):
    cards = get_active_cards()
    print(f"-> {total_count} ATM operations started")
    
    for i in range(total_count):
        card = random.choice(cards)
        op_type = random.choice(['deposit', 'withdrawal'])
        amount = random.randint(10000, 1000000)
        try:
            cursor.execute("{CALL sp_AtmOperation (?, ?, ?)}", (card.id, amount, op_type))
            if i % 50 == 0: conn.commit()
        except:
            continue
        time.sleep(2)
    conn.commit()
    print(f"   OK: ATM operations finished")

# sp_ApplyCashback 
def simulate_cashback():
    print("Calculating Cashback")
    cursor.execute("SELECT id FROM transactions WHERE status='success' AND is_flagged = 0")
    tx_ids = [row[0] for row in cursor.fetchall()]
    
    for i, tx_id in enumerate(tx_ids):
        try:
            cursor.execute("{CALL sp_ApplyCashback (?, ?)}", (tx_id, 1.0))
            if i % 100 == 0: conn.commit()
        except:
            continue
        time.sleep(1)
    conn.commit()
    print(f"   OK: {len(tx_ids)} Cachbacks checked.")


# Other store procs
def run_maintenance():
    print("Updating system reports and payments...")
    try:
        cursor.execute("{CALL sp_ProcessScheduledPayments}")
        cursor.execute("{CALL sp_GenerateReports (?)}", ('daily'))
        conn.commit()
        print("   OK: Reports ready.")
    except Exception as e:
        print(f"   Error: {e}")

# Main
if __name__ == "__main__":
    start_time = time.time()
    
    simulate_transfers(1000) 
    simulate_atm(200)
    simulate_cashback()
    run_maintenance()
    
    end_time = time.time()
    print(f"\nOperations finished: {round(end_time - start_time, 2)} seconds.")
    
    cursor.close()
    conn.close()