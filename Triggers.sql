-- Trigger for updating balance of users
CREATE TRIGGER trg_UpdateTotalBalance ON cards
AFTER INSERT, UPDATE, DELETE
AS 
BEGIN
    SET NOCOUNT ON;
    DECLARE @AffectedUsers TABLE (UserID INT);
    
    INSERT INTO @AffectedUsers
    SELECT user_id FROM inserted WHERE user_id IS NOT NULL
    UNION
    SELECT user_id FROM deleted WHERE user_id IS NOT NULL;

    UPDATE u
    SET u.total_balance = (SELECT ISNULL(SUM(c.balance), 0) FROM cards c WHERE c.user_id = u.id)
    FROM users u
    INNER JOIN @AffectedUsers au ON u.id = au.UserID;
END;

--Trigger for block card if breaks limit
CREATE TRIGGER trg_BlockCard 
ON cards
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF UPDATE(balance) OR UPDATE(limit_amount)
    BEGIN
        UPDATE c
        SET c.is_blocked = 1
        FROM cards c
        INNER JOIN inserted i ON c.id = i.id
        WHERE i.balance > i.limit_amount 
          AND c.is_blocked = 0;          
    END
END;

-- Trigger for control large transactions
CREATE TRIGGER trg_Fraud_150M ON transactions
AFTER INSERT
AS 
BEGIN
	SET NOCOUNT ON;
	UPDATE transactions
	SET is_flagged = 1
	FROM transactions T JOIN inserted I ON T.id = I.id
	WHERE I.amount >= 150000000;

	INSERT INTO fraud_detection (transaction_id, user_id, reason, status)
	SELECT I.id, C.user_id, 'Transaction exceeded the limit (150mln+)', 'pending'
	FROM cards C JOIN inserted I ON C.id = I.from_card_id
	WHERE I.amount >= 150000000
END;

--Trigger for give VIP status automaticly
CREATE TRIGGER trg_AutoVIP ON users
AFTER UPDATE
AS
BEGIN
	SET NOCOUNT ON;
	IF UPDATE(total_balance)
	BEGIN
		INSERT INTO vip_users (user_id, reason)
		SELECT I.id, 'The total balance exceeded 900 mln' FROM inserted I LEFT JOIN vip_users V ON I.id = V.user_id
		WHERE I.total_balance >= 900000000 AND V.user_id IS NULL;

		UPDATE users
		SET is_vip = 1
		WHERE ID IN (SELECT ID FROM inserted WHERE total_balance >= 900000000);
	END
END;

--Trigger for Welcome Bonus
CREATE TRIGGER trg_WelcomeBonus ON users
AFTER INSERT
AS
BEGIN
	SET NOCOUNT ON;
	INSERT INTO logs (message)
	SELECT 'Welcome Bonus is ready for new user: '+ name  FROM inserted;
END;

--Trigger for Block suspicious transactions
CREATE TRIGGER trg_VelocityCheck ON transactions
AFTER INSERT
AS 
BEGIN
	SET NOCOUNT ON;
	DECLARE @CardID INT, @UserID INT;
	SELECT @CardID = from_card_id FROM inserted;
	SELECT @UserID = user_id FROM cards WHERE id = @CardID

	IF (SELECT COUNT(*) FROM transactions
		WHERE from_card_id = @CardID AND
		created_at >= DATEADD(MINUTE, -5, GETDATE())) >= 3
	BEGIN
		UPDATE cards SET is_blocked = 1 WHERE id = @CardID;

		INSERT INTO fraud_detection (transaction_id, user_id, reason ,status)
		SELECT id, @UserID, '3 transactions in 5 minutes (Velocity limit)', 'blocked' FROM inserted;
	END
END;


--Trigger for Automatic savings
CREATE TRIGGER trg_SavingPlan_5Percent ON transactions
AFTER INSERT
AS
BEGIN
	SET NOCOUNT ON;
	IF (SELECT status FROM inserted) = 'success' AND (SELECT transaction_type FROM inserted) = 'transfer'
	BEGIN
		DECLARE @SenderUserID INT, @SavingCardID INT, @Amount BIGINT;

		SELECT @Amount = amount * 0.05 FROM inserted;
		SELECT @SenderUserID = C.user_id FROM inserted I JOIN cards C ON I.from_card_id = C.id;

		SELECT TOP 1 @SavingCardID = id FROM cards
		WHERE is_blocked = 0 AND card_type = 'savings' AND user_id = @SenderUserID
		ORDER BY created_at ASC;

		IF @SavingCardID IS NOT NULL
		BEGIN
			UPDATE cards SET balance = balance + @Amount WHERE id = @SavingCardID
			UPDATE cards SET balance = balance - @Amount WHERE id = (SELECT from_card_id FROM inserted);
		END
	END
END;


--Trigger for Audit of transactions
CREATE TRIGGER trg_AuditLogs_StatusChange ON transactions
AFTER UPDATE
AS 
BEGIN 
	SET NOCOUNT ON;
	IF UPDATE(status)
	BEGIN 
		INSERT INTO logs (transaction_id, message)
		SELECT I.id, 'Transaction status changed: ' + D.status + '->' + I.STATUS 
		FROM inserted AS I JOIN deleted AS D ON I.id = D.id;
	END
END;


--Trigger for unusual movement analysis
CREATE TRIGGER trg_AnomalousActivity ON transactions
AFTER INSERT
AS 
BEGIN
	SET NOCOUNT ON;
	DECLARE @AvgAmount BIGINT , @CurrentAmount BIGINT, @SenderCardID INT

	SELECT @SenderCardID = from_card_id, @CurrentAmount = amount FROM inserted;

	SELECT @AvgAmount = AVG(amount) FROM 
							(SELECT TOP 10 amount FROM inserted WHERE from_card_id = @SenderCardID ORDER BY created_at DESC) AS H;

	IF @CurrentAmount > (@AvgAmount * 10) AND @AvgAmount > 0
	BEGIN
		UPDATE transactions SET is_flagged = 1 WHERE id IN (SELECT id FROM inserted);
		
		INSERT INTO logs (transaction_id, message)
		SELECT id, 'Anomalous movement: 10 times higher the average amount' FROM inserted
	END
END;	


