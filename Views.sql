-- 1. User financial portrait
CREATE VIEW vw_UserFinancialStatus AS
SELECT 
    u.id AS user_id,
    u.name,
    u.status AS user_status,
    u.is_vip,
    COUNT(c.id) AS total_cards,
    ISNULL(SUM(c.balance), 0) AS total_balance,
    u.created_at AS registration_date
FROM users u
LEFT JOIN cards c ON u.id = c.user_id
GROUP BY u.id, u.name, u.status, u.is_vip, u.created_at;
GO

-- 2. Suspicious transaction monitoring
CREATE VIEW vw_FraudulentActivities AS
SELECT 
    t.id AS transaction_id,
    t.from_card_id,
    c.user_id AS sender_id,
    u.name AS sender_name,
    t.amount,
    t.created_at,
    fd.reason AS fraud_reason,
    fd.status AS investigation_status
FROM transactions t
JOIN cards c ON t.from_card_id = c.id
JOIN users u ON c.user_id = u.id
JOIN fraud_detection fd ON t.id = fd.transaction_id
WHERE t.is_flagged = 1;
GO

-- 3. Daily bank turnover
CREATE VIEW vw_BankDailySummary AS
SELECT 
    CAST(created_at AS DATE) AS operation_date,
    COUNT(id) AS total_transactions_count,
    ISNULL(SUM(CASE WHEN status = 'success' THEN amount ELSE 0 END), 0) AS successful_volume,
    SUM(CASE WHEN is_flagged = 1 THEN 1 ELSE 0 END) AS flagged_count,
    SUM(CASE WHEN transaction_type = 'transfer' THEN 1 ELSE 0 END) AS transfer_count,
    SUM(CASE WHEN transaction_type = 'withdrawal' THEN 1 ELSE 0 END) AS withdrawal_count,
    SUM(CASE WHEN transaction_type = 'deposit' THEN 1 ELSE 0 END) AS deposit_count
FROM transactions
GROUP BY CAST(created_at AS DATE);
GO

-- 4. Audit of blocked users
CREATE VIEW vw_BlockedUserDetails AS
SELECT 
    u.id,
    u.name,
    bu.reason AS block_reason,
    bu.blocked_at,
    u.total_balance AS frozen_funds
FROM users u
JOIN blocked_users bu ON u.id = bu.user_id
WHERE u.status = 'blocked';
GO

-- 5. Active loans and debts
CREATE VIEW vw_ActiveLoans AS
SELECT 
    sp.id AS payment_id,
    u.name AS debtor_name,
    sp.amount AS due_amount,
    sp.payment_date,
    sp.status AS payment_status
FROM scheduled_payments sp
JOIN users u ON sp.user_id = u.id
WHERE sp.status IN ('pending', 'failed');
GO

-- 6. Card usage analysis
CREATE VIEW vw_CardUsageAnalytics AS
SELECT 
    card_type,
    COUNT(id) AS total_cards,
    ISNULL(SUM(balance), 0) AS total_balance_on_cards,
    ISNULL(AVG(balance), 0) AS average_balance,
    SUM(CASE WHEN is_blocked = 1 THEN 1 ELSE 0 END) AS blocked_cards_count,
    CAST(SUM(CASE WHEN is_blocked = 1 THEN 1.0 ELSE 0.0 END) / COUNT(id) * 100 AS DECIMAL(5,2)) AS block_rate_percentage
FROM cards
GROUP BY card_type;
GO

-- 7. VIP customer service
CREATE VIEW vw_VipCustomerService AS
SELECT 
    u.id, u.name, u.phone_number, u.total_balance, u.last_active_at,
    (SELECT COUNT(*) FROM transactions t JOIN cards c ON t.from_card_id = c.id WHERE c.user_id = u.id) AS total_tx_count
FROM users u
WHERE u.is_vip = 1 AND u.status = 'active';
GO

-- Payments in a week
CREATE VIEW vw_UpcomingPayments AS
SELECT 
    sp.id, u.name, sp.amount, sp.payment_date,
    DATEDIFF(DAY, GETDATE(), sp.payment_date) AS days_left,
    CASE WHEN c.balance >= sp.amount THEN 'Ready' ELSE 'Low Balance' END AS fund_status
FROM scheduled_payments sp
JOIN users u ON sp.user_id = u.id
JOIN cards c ON sp.card_id = c.id
WHERE sp.status = 'pending' AND sp.payment_date BETWEEN GETDATE() AND DATEADD(DAY, 7, GETDATE());
GO

-- User Monitoring (With Block History)
CREATE VIEW vw_UserMonitoring AS
SELECT 
    u.id, u.name, u.status,
    CASE WHEN u.is_vip = 1 THEN 'VIP' ELSE 'Standard' END AS membership,
    (SELECT COUNT(*) FROM blocked_users WHERE user_id = u.id) AS block_count,
    u.total_balance, u.last_active_at
FROM users u;
GO

--  Customer Retention Risk
CREATE VIEW vw_CustomerRetentionRisk AS
SELECT 
    id, name, total_balance, last_active_at,
    DATEDIFF(DAY, last_active_at, GETDATE()) AS inactive_days,
    CASE 
        WHEN DATEDIFF(DAY, last_active_at, GETDATE()) > 60 THEN 'High Risk'
        WHEN DATEDIFF(DAY, last_active_at, GETDATE()) BETWEEN 20 AND 60 THEN 'Medium Risk'
        ELSE 'Active'
    END AS risk_level
FROM users WHERE status = 'active';
GO