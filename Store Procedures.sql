--Store procedure for inserting data into transactions
CREATE PROC sp_MakeTransfer
		@FromCardID INT,
		@ToCardID INT,
		@Amount BIGINT
AS
BEGIN
	SET NOCOUNT ON;
	IF @FromCardID = @ToCardID
	BEGIN
		RAISERROR('Cannot transfer money to yourself.', 16, 1);
		RETURN;
	END

	IF @Amount <= 0
	BEGIN
		RAISERROR('Amount must be higher than 0.', 16,1);
		RETURN;
	END

	BEGIN TRAN
	BEGIN TRY
		DECLARE @SenderBalance BIGINT, @SenderBlocked BIT
		SELECT @SenderBalance = balance, @SenderBlocked = is_blocked FROM cards WITH (UPDLOCK) WHERE id = @FromCardID;

		IF @SenderBalance < @Amount OR @SenderBlocked = 1
		BEGIN 
			THROW 50001, 'Sender Card is blocker or insufficent amount.', 1;
		END

		IF NOT EXISTS (SELECT 1 FROM cards WHERE id = @ToCardID AND is_blocked = 0)
        BEGIN
            THROW 50002, 'Receiving card is not available or blocked.', 1;
        END

		UPDATE cards SET balance = balance - @Amount WHERE id = @FromCardID;
        UPDATE cards SET balance = balance + @Amount WHERE id = @ToCardID;

		INSERT INTO transactions (from_card_id, to_card_id, amount, status, transaction_type, created_at)
        VALUES (@FromCardID, @ToCardID, @Amount, 'success', 'transfer', GETDATE());

		COMMIT TRAN
	END TRY
	BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @Msg NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@Msg, 16, 1);
    END CATCH
END;


--Store Procedure for Deposit and withdrawal
CREATE PROC sp_AtmOperation
	@CardID INT,
	@Amount BIGINT,
	@Type VARCHAR(20)
AS
BEGIN
	SET NOCOUNT ON;
	IF @Amount <= 0 
	BEGIN
		RAISERROR('Incorrect amount.', 16, 1);
	END

	BEGIN TRAN
	BEGIN TRY
		IF @Type = 'withdrawal'
		BEGIN
			IF EXISTS (SELECT 1 FROM cards WHERE id = @CardID AND (is_blocked = 1 OR balance < @Amount))
			THROW 500003, 'Unable to resolve: insufficient balance or card blocked.', 1;
			
			UPDATE cards SET balance = balance - @Amount WHERE id = @CardID;
		END
		ELSE IF @Type = 'deposit'
		BEGIN
			UPDATE cards SET balance = balance + @Amount WHERE id = @CardID;
		END

		INSERT INTO transactions (from_card_id, amount, status, transaction_type, created_at)
		VALUES (@CardID, @Amount, 'success', @Type, GETDATE())

		COMMIT TRAN
	END TRY
	BEGIN CATCH 
		IF @@TRANCOUNT > 0 ROLLBACK TRAN;
		THROW;
	END CATCH
END;


--Store Procedure for generate scheduled payments
CREATE PROC sp_ProcessScheduledPayments 
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @PaymentID INT, @FromCardID INT, @Amount BIGINT;

	DECLARE PAY_CUR CURSOR FOR
	SELECT id, card_id, amount FROM scheduled_payments
	WHERE status = 'pending' AND payment_date <= GETDATE();

    OPEN PAY_CUR;
    FETCH NEXT FROM PAY_CUR INTO @PaymentID, @FromCardID, @Amount;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            EXEC sp_MakeTransfer @FromCardID, 1, @Amount;
            UPDATE scheduled_payments SET status = 'completed' WHERE id = @PaymentID;
        END TRY
        BEGIN CATCH
            UPDATE scheduled_payments SET status = 'failed' WHERE id = @PaymentID;
        END CATCH
        FETCH NEXT FROM PAY_CUR INTO @PaymentID, @FromCardID, @Amount;
    END

    CLOSE PAY_CUR;
    DEALLOCATE PAY_CUR;
END;
	

--Store Procedure for emrgency blocking cards
CREATE PROC sp_EmergencyBlock
	@UserID INT,
	@CardID INT,
	@Reason VARCHAR(MAX)
AS
BEGIN
	SET NOCOUNT ON;
	UPDATE cards SET is_blocked = 1 WHERE id = @CardID AND user_id = @UserID;

	INSERT INTO blocked_users (user_id, reason, blocked_at)
	VALUES(@UserID, @Reason, GETDATE());

	INSERT INTO logs (message, created_at)
	VALUES('Card Blocked. UserID: ' + CAST(@UserID AS VARCHAR), GETDATE());
END;


--Store procedure for verify and transfer 
CREATE PROC sp_VerifyAndTransfer_2FA
	@FromCardID INT,
	@ToCardID INT,
	@Amount BIGINT,
	@OTPCode INT
AS
BEGIN
	SET NOCOUNT ON;
	IF @Amount >= 150000000 AND (@OTPCode IS NULL OR @OTPCode <> '123456')
	BEGIN
		RAISERROR('2FA code for large transaction is incorrect!', 16, 1);
	END
	ELSE
	BEGIN
		EXEC sp_MakeTransfer @FromCardID, @ToCardID, @Amount;
	END
END;


--Store Procedure for giving loan
CREATE PROC sp_ApplyLoan
	@UserID INT,
	@CardID INT,
	@LoanAmount BIGINT
AS 
BEGIN
	SET NOCOUNT ON;
	UPDATE cards SET balance = balance + @LoanAmount WHERE id = @CardID AND user_id = @UserID

	INSERT INTO scheduled_payments (user_id, card_id, amount, payment_date, status)
	VALUES(@UserID, @CardID, @LoanAmount * 1.1, DATEADD(MONTH, 1,GETDATE()), 'pending');

	INSERT INTO logs (message) VALUES('Loan given. Amount: '+CAST(@LoanAmount AS VARCHAR))
END;


--Store Procedure for trensferring to heirs
CREATE PROC sp_TransferToHeirs
	@DeadUserID INT,
	@HeirCardID INT
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @Wealth BIGINT = (SELECT total_balance FROM users WHERE id = @DeadUserID);

	IF @Wealth > 0
	BEGIN 
		UPDATE cards SET balance = balance + @Wealth WHERE id = @HeirCardID;
		UPDATE cards SET balance = 0, is_blocked = 1 WHERE user_id = @DeadUserID;
		UPDATE users SET status = 'blocked', total_balance = 0 WHERE id = @DeadUserID;

		INSERT INTO blocked_users (user_id, blocked_at, reason)
		VALUES(@DeadUserID, GETDATE(), 'User is Dead');

		INSERT INTO logs (message) VALUES('The deceased user''s wealth were transferred to the heir. UserID: '+CAST(@DeadUserID AS VARCHAR));
	END
END;


--Store Procedure for giving cashback
CREATE PROC sp_ApplyCashback
	@TransactionID INT,
	@Percent DECIMAL(4,2) = 1.00
AS
BEGIN 
	SET NOCOUNT ON;
	DECLARE @Amount BIGINT, @CardID INT

	SELECT @Amount = amount, @CardID = from_card_id FROM transactions WHERE id = @TransactionID AND status = 'success'

	IF @CardID IS NOT NULL AND EXISTS (SELECT 1 FROM cards WHERE is_blocked = 0 AND id = @CardID)
	BEGIN 
		UPDATE cards SET balance = balance + (@Amount * @Percent / 100) WHERE id = @CardID;
		INSERT INTO logs (transaction_id, message) VALUES(@TransactionID, 'Cashback added');
	END
END;

--Store Procedure for genereting reports
CREATE PROC sp_GenerateReports
	@Type VARCHAR(20)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @Start DATETIME2 =
		CASE	
			WHEN @Type = 'daily' THEN DATEADD(DAY, -1, GETDATE())
			WHEN @Type = 'weekly' THEN DATEADD(WEEK, -1, GETDATE())
			WHEN @Type = 'monthly' THEN DATEADD(MONTH, -1, GETDATE())
			ELSE NULL
		END;

	IF @Start IS NOT NULL
	BEGIN 
		INSERT INTO reports (report_type, total_amount, total_transactions, flagged_transactions, created_at)
		SELECT 
		@Type,
		ISNULL(SUM(amount), 0),
		COUNT(id),
		SUM(CASE WHEN is_flagged = 1 THEN 1 ELSE 0 END),
		GETDATE()
		FROM transactions WHERE created_at >= @Start;
	END
END;

