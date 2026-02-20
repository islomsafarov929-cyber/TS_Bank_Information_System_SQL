--CREATE DATABASE TZ_BANK_test
--GO
--USE TZ_BANK_test

--1) 
CREATE TABLE users (
    id INT IDENTITY(1,1) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    phone_number VARCHAR(20) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE,
    created_at DATETIME2 DEFAULT CURRENT_TIMESTAMP,
    last_active_at DATETIME2,
    status VARCHAR(20) DEFAULT 'active', -- active, blocked, vip
    is_vip BIT NOT NULL DEFAULT 0, -- VIP foydalanuvchilar uchun
    total_balance BIGINT DEFAULT 0 -- Umumiy balans
);

--2)
CREATE TABLE cards (
    id INT IDENTITY(1,1) PRIMARY KEY,
    user_id INT REFERENCES users(id) ON DELETE CASCADE,
    card_number VARCHAR(16) UNIQUE NOT NULL,
    balance BIGINT DEFAULT 0,
    is_blocked BIT NOT NULL DEFAULT 0,
    created_at DATETIME2 DEFAULT CURRENT_TIMESTAMP,
    card_type VARCHAR(20) CHECK (card_type IN ('debit', 'credit', 'savings')), -- Karta turi
    limit_amount BIGINT DEFAULT 150000000 -- Limitdan oshsa bloklanadi
);

--3)
CREATE TABLE transactions (
    id INT IDENTITY(1,1) PRIMARY KEY,
    from_card_id INT REFERENCES cards(id) ON DELETE CASCADE,
    to_card_id INT REFERENCES cards(id) ON DELETE NO ACTION,
    amount BIGINT NOT NULL,
    status VARCHAR(20) CHECK (status IN ('pending', 'success', 'failed')) DEFAULT 'pending',
    created_at DATETIME2 DEFAULT CURRENT_TIMESTAMP,
    transaction_type VARCHAR(20) CHECK (transaction_type IN ('transfer', 'withdrawal', 'deposit')),
    is_flagged BIT NOT NULL DEFAULT 0 -- Shubhali tranzaksiyalarni aniqlash uchun
);

--4)
CREATE TABLE logs (
    id INT IDENTITY(1,1) PRIMARY KEY,
    transaction_id INT REFERENCES transactions(id) ON DELETE CASCADE,
    message VARCHAR(255) NOT NULL,
    created_at DATETIME2 DEFAULT CURRENT_TIMESTAMP
);

--5)
CREATE TABLE reports (
    id INT IDENTITY(1,1) PRIMARY KEY,
    report_type VARCHAR(50), -- daily, weekly, monthly
    created_at DATETIME2 DEFAULT CURRENT_TIMESTAMP,
    total_transactions BIGINT DEFAULT 0,
    flagged_transactions BIGINT DEFAULT 0, -- Shubhali tranzaksiyalar
    total_amount BIGINT DEFAULT 0
);

--6)
CREATE TABLE fraud_detection (
    id INT IDENTITY(1,1) PRIMARY KEY,
    transaction_id INT REFERENCES transactions(id) ON DELETE CASCADE,
    user_id INT REFERENCES users(id) ON DELETE NO ACTION,
    reason VARCHAR(255) NOT NULL, -- Shubhali harakat sababi
    status VARCHAR(20) CHECK (status IN ('pending', 'reviewed', 'blocked')) DEFAULT 'pending',
    created_at DATETIME2 DEFAULT CURRENT_TIMESTAMP
);

--7)
CREATE TABLE scheduled_payments (
    id INT IDENTITY(1,1) PRIMARY KEY,
    user_id INT REFERENCES users(id) ON DELETE CASCADE,
    card_id INT REFERENCES cards(id) ON DELETE NO ACTION,
	loan_id INT REFERENCES loans(id) ON UPDATE CASCADE,
    amount BIGINT NOT NULL,
    payment_date DATETIME2 NOT NULL,
    status VARCHAR(20) CHECK (status IN ('pending', 'completed', 'failed')) DEFAULT 'pending',
    created_at DATETIME2 DEFAULT CURRENT_TIMESTAMP
);


--8)
CREATE TABLE vip_users (
    id INT IDENTITY(1,1) PRIMARY KEY,
    user_id INT REFERENCES users(id) ON DELETE CASCADE,
    assigned_at DATETIME2 DEFAULT CURRENT_TIMESTAMP,
    reason VARCHAR(255) NOT NULL -- VIP bo‘lish sababi (mablag‘ miqdori, tranzaksiya hajmi va h.k)
);

--9)
CREATE TABLE blocked_users (
    id INT IDENTITY(1,1) PRIMARY KEY,
    user_id INT REFERENCES users(id) ON DELETE CASCADE,
    blocked_at DATETIME2 DEFAULT CURRENT_TIMESTAMP,
    reason VARCHAR(255) NOT NULL
);

--10)
CREATE TABLE Loans (
	id INT IDENTITY(1,1) PRIMARY KEY, 
	user_id INT REFERENCES users(id) ON DELETE NO ACTION,
	card_id INT REFERENCES cards(id) ON DELETE CASCADE,
	amount BIGINT NOT NULL,
	interest_Rate DECIMAL(5,2),
	total_Repayment DECIMAL(18,2),
	paid_Amount DECIMAL(18,2) DEFAULT 0,
	status VARCHAR(20) CHECK (status in ('active', 'paid', 'overdue')),
	created_at DATETIME2 DEFAULT CURRENT_TIMESTAMP,
	ends_at DATETIME2
)
