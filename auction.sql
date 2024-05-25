USE AdventureWorks
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'Auction')
    BEGIN
        EXEC('CREATE SCHEMA Auction')
    END
GO



IF NOT EXISTS(SELECT *
              FROM sys.tables
              WHERE name = 'AuctionedProducts')
    BEGIN
		CREATE TABLE Auction.AuctionedProducts
		(
			AuctionID int IDENTITY PRIMARY KEY,
			ProductID int,
			StartDate datetime NOT NULL,
			ExpireDate datetime NOT NULL,
			EndDate datetime,
			InitialBidPrice money NOT NULL,
			Status NVARCHAR(10) NOT NULL,
			WinnerBid int,
			CONSTRAINT FK_ProductID FOREIGN KEY (ProductID) REFERENCES Production.Product (ProductID),
			CONSTRAINT CK_AuctionedProducts CHECK ((ExpireDate IS NULL AND InitialBidPrice IS NULL) OR
                                                   (ExpireDate IS NOT NULL AND InitialBidPrice IS NOT NULL)),
			CONSTRAINT CK_Status CHECK (Status IN ('Active','Closed','Cancelled'))
		);
	END
GO

IF NOT EXISTS(SELECT *
        FROM sys.tables
        WHERE name = 'Bids')
	BEGIN
		CREATE TABLE Auction.Bids 
		(
			BidID int IDENTITY(1,1) PRIMARY KEY,
			CustomerID int NOT NULL,
			AuctionID  int   NOT NULL,
			BidAmount money NOT NULL,
			BidDate datetime NOT NULL,
			CONSTRAINT FK_AuctioID FOREIGN KEY (AuctionID) REFERENCES Auction.AuctionedProducts (AuctionID),
			CONSTRAINT FK_CustomerID FOREIGN KEY (CustomerID) REFERENCES Sales.Customer (CustomerID)
		);
	END;
GO

IF NOT EXISTS(SELECT *
              FROM sys.tables
              WHERE name = 'Threshold')
    BEGIN
		CREATE TABLE Auction.Threshold
		(
			ThresholdID int IDENTITY (1,1) NOT NULL,
			MinimumIncreaseBid money NOT NULL,
			MaxAuctionPrice float NOT NULL,
			MinStartDate datetime NOT NULL,
			MaxExpireDate datetime NOT NULL,
			CONSTRAINT CK_MaxAuctionPrice CHECK (MaxAuctionPrice > 0 AND MaxAuctionPrice <= 1)
		);

		INSERT INTO Auction.Threshold (MinimumIncreaseBid, MaxAuctionPrice ,MinStartDate, MaxExpireDate) VALUES (0.05, 1, '2023-11-13 00:00:00', '2023-11-26 23:59:59');
	END
GO

CREATE OR ALTER PROCEDURE Auction.uspAddProductToAuction( @ProductID int, @ExpireDate datetime = NULL, @InitialBidPrice money= NULL)
AS
BEGIN

--CHECK IF PRODUCT EXIST and is currently in sale and have stock to be cleared
	IF NOT EXISTS(SELECT ProductID FROM Production.Product AS p WHERE ProductID = @ProductID AND SellEndDate IS NULL  AND DiscontinuedDate IS NULL AND dbo.ufnGetStock(@ProductID) > 0)
		BEGIN
			RAISERROR ('Product not available for auction', 16, 1)
			RETURN
		END

--CHECK IF PRODUCT IS ALREADY ADDED TO AUCTION
	IF EXISTS( SELECT ProductID FROM Auction.AuctionedProducts WHERE ProductID = @ProductID AND Status = 'Active')
		BEGIN
			RAISERROR ('Product already added to auction',16,1)
			RETURN
		END

--CHECK INSERTION DATE IN UTC TIME IS BEFORE AUCTION END LIMIT
	DECLARE @MinStartDate datetime
	DECLARE @MaxExpireDate datetime
	DECLARE @MinimumIncreaseBid money
	DECLARE @MaxAuctionPrice float

	SELECT @MinStartDate = MinStartDate, @MaxAuctionPrice = MaxAuctionPrice, @MaxExpireDate = MaxExpireDate, @MinimumIncreaseBid = MinimumIncreaseBid FROM Auction.Threshold

	IF  @MaxExpireDate < GETUTCDATE()
		BEGIN
			RAISERROR ('The Auction period is over. You cannot insert more Products for auction', 16, 1)
			RETURN
		END

--CHECK @ExpiredDate AND ADJUST IF NEEDED

	DECLARE @StartDate datetime

	IF GETUTCDATE() < @MinStartDate
		BEGIN
			SET @StartDate = @MinStartDate
		END
	ELSE
		BEGIN
			SET @StartDate = GETUTCDATE()
		END
	
	IF @ExpireDate IS NOT NULL
		BEGIN
			IF @ExpireDate < @MinStartDate
				BEGIN
					DECLARE @msgtext varchar(100)
					SET @msgtext = CONCAT('Expire date should be greater than',@MinStartDate)
					RAISERROR (@msgtext, 16, 1)
					RETURN
				END
			IF @ExpireDate < GETUTCDATE()
				BEGIN
					RAISERROR ('Expire date should be greater than the current date!', 16, 1)
					RETURN
				END
			--IF @ExpireDate > @MaxExpireDate --CONVERT(DATETIME,'2023-11-26 23:59:59')
			--	BEGIN
			--		SET @ExpireDate = @MaxExpireDate  ---'2023-11-26 23:59:59'
			--	END
		END
	ELSE
		BEGIN
			IF DATEADD(d,7,@MinStartDate) <  @MaxExpireDate    --(SELECT DATEDIFF(second, DATEADD(d,7,GETUTCDATE()), (SELECT CONVERT(DATETIME,'2023-11-26 23:59:59')))) > 0
				BEGIN
					SET @ExpireDate = DATEADD(d,7,@MinStartDate)
				END
			ELSE
				BEGIN
					SET @ExpireDate = @MaxExpireDate
				END
		END

--CHECK IF @InitialBidPrice VALIDITY
--IF NOT null
	--Lower than Mininum allowed bid set it to the Mininum
	--Higher than Maximum allowed bid set it to the List Price - MinIncreaseBid to allow 1 bid
--IF NULL
	--Set to the minimum allowed

	DECLARE @MakeFlag bit
	DECLARE @MaxBidPrice money
	SELECT @MakeFlag = MakeFlag, @MaxBidPrice = ListPrice*@MaxAuctionPrice
	FROM Production.Product
	WHERE ProductID = @ProductID
	
	DECLARE @MinBidPrice money

	If @MakeFlag = 0
		BEGIN
			SELECT @MinBidPrice = ListPrice * 0.75
			FROM Production.Product
			WHERE ProductID = @ProductID
		END
	ELSE
		BEGIN
			SELECT @MinBidPrice = ListPrice * 0.5
			FROM Production.Product
			WHERE ProductID = @ProductID
		END

	IF @InitialBidPrice IS NOT NULL
		BEGIN
			IF @InitialBidPrice < @MinBidPrice
				BEGIN
					SET @InitialBidPrice = @MinBidPrice
				END
			IF @InitialBidPrice > @MaxBidPrice
				BEGIN
					SET @InitialBidPrice = @MaxBidPrice - @MinimumIncreaseBid
				END
		END
	ELSE
		BEGIN
			SET @InitialBidPrice = @MinBidPrice
		END

	INSERT INTO Auction.AuctionedProducts(ProductID, StartDate, ExpireDate, EndDate, InitialBidPrice, Status)
	VALUES (@ProductID, @StartDate, @ExpireDate, NULL, @InitialBidPrice, 'Active')
END
GO

CREATE OR ALTER PROCEDURE Auction.uspTryBidProduct (@ProductID int, @CustomerID int, @BidAmount money = NULL)
AS
BEGIN

	DECLARE @AuctionID int
	DECLARE @InitialBidPrice money

	SELECT @AuctionID = AuctionID, @InitialBidPrice = InitialBidPrice
	FROM Auction.AuctionedProducts
	WHERE ProductID = @ProductID AND Status = 'Active'
	
	DECLARE @MinIncrease money
	DECLARE @MaxAuctionPrice float
	DECLARE @ExpireDate datetime
	DECLARE @MaxBidDate datetime
	SELECT @MinIncrease = MinimumIncreaseBid, @MaxAuctionPrice = MaxAuctionPrice, @MaxBidDate = MaxExpireDate
	FROM Auction.Threshold

	DECLARE @MaxBidPrice money
	SELECT @MaxBidPrice = ListPrice * @MaxAuctionPrice
	FROM Production.Product
	WHERE ProductID = @ProductID

--CHECK CustomerID EXISTS
	IF NOT EXISTS (SELECT CustomerID FROM Sales.Customer WHERE CustomerID = @CustomerID)
		BEGIN
			RAISERROR('Please register has a customer before auction',16,1)
			RETURN
		END

--CHECK IF PRODUCT IS IN AUCTION
	IF NOT EXISTS (SELECT ProductID FROM Auction.AuctionedProducts WHERE ProductID = @ProductID AND Status = 'Active') OR (GETUTCDATE() > (SELECT ExpireDate FROM Auction.AuctionedProducts WHERE ProductID = @ProductID AND Status = 'Active') OR GETUTCDATE() > @MaxBidDate)
		BEGIN
			RAISERROR('Product not available for Auction',16,1)
			RETURN
		END
	ELSE IF GETUTCDATE() < (SELECT StartDate FROM Auction.AuctionedProducts WHERE ProductID = @ProductID AND Status = 'Active')
		BEGIN
			RAISERROR('Too early to bid this product',16,1)
			RETURN
		END

--CHECK IF @BidAmount is valid


--Check BidAmount validit
	DECLARE @MaxBid money
	SELECT @MaxBid = MAX(BidAmount)
	FROM Auction.Bids
	WHERE AuctionID = @AuctionID

	IF @BidAmount IS NULL
		BEGIN
			IF  @MaxBid IS NULL
				BEGIN
					SET @BidAmount = @InitialBidPrice
				END
			ELSE
				BEGIN
					SET @BidAmount = @MaxBid+@MinIncrease
				END
		END
	ELSE
		BEGIN
			IF @BidAmount < @MaxBid+@MinIncrease
				BEGIN
					RAISERROR('Bid too Low!',16,1)
					RETURN
				END
		END

--CHECK IF @BidAmount is above ListPrice
	IF @BidAmount > @MaxBidPrice 
		BEGIN
			RAISERROR('Bid amount is above the limit',16,1)
			RETURN
		END

--INSERT INTO TABLE
	INSERT INTO Auction.Bids (CustomerID, AuctionID, BidAmount, BidDate)
	VALUES (@CustomerID, @AuctionID, @BidAmount, GETUTCDATE())

END
GO


CREATE OR ALTER PROCEDURE Auction.upsRemoveProductFromAuction (@ProductID INT)
AS
BEGIN
	IF NOT EXISTS(SELECT @ProductID FROM Auction.AuctionedProducts WHERE ProductID = @ProductID AND Status = 'Active')
		BEGIN
			RAISERROR ('Product not in Auction', 16, 1);
			RETURN;
		END
	ELSE
		BEGIN
			UPDATE Auction.AuctionedProducts
			SET Status = 'Cancelled', EndDate = GETUTCDATE()
			WHERE ProductID = @ProductID AND Status = 'Active'
		END
END
GO

CREATE OR ALTER PROCEDURE Auction.upsListBidOffersHistory(@CustomerID INT, @StartTime datetime, @EndTime datetime, @Active bit = 1)
AS
BEGIN
	IF NOT EXISTS(SELECT CustomerID FROM Auction.Bids WHERE CustomerID = @CustomerID)
		BEGIN
			RAISERROR ('The inserted Customer never bid a product!', 16, 1);
			RETURN;
		END
	ELSE
		BEGIN
			IF @Active = 1
				BEGIN
					 (SELECT b.BidID, b.AuctionID, a.ProductID, b.BidAmount, b.BidDate
							FROM Auction.Bids as b
							JOIN Auction.AuctionedProducts as a
							ON b.AuctionID = a.AuctionID
							WHERE b.CustomerID = @CustomerID AND b.BidDate >= @StartTime AND b.BidDate <= @EndTime AND a.Status = 'Active')
				END
			ELSE
				BEGIN
					 (SELECT b.BidID, b.AuctionID, a.ProductID, b.BidAmount, b.BidDate
							FROM Auction.Bids as b
							JOIN Auction.AuctionedProducts as a
							ON b.AuctionID = a.AuctionID
							WHERE b.CustomerID = @CustomerID AND b.BidDate >= @StartTime AND b.BidDate <= @EndTime)
				END
		END
END
GO

CREATE OR ALTER PROCEDURE Auction.uspUpdateAuctionStatus
AS
BEGIN
	BEGIN TRY
		BEGIN TRANSACTION
			UPDATE Auction.AuctionedProducts
			SET WinnerBid = (SELECT TOP 1 BidID
			FROM Auction.AuctionedProducts p
			JOIN Auction.Bids b ON b.AuctionID = p.AuctionID
			WHERE p.Status = 'Active' AND p.ExpireDate < GETUTCDATE() 
			ORDER BY b.BidAmount desc)
			WHERE AuctionID IN (SELECT P.AuctionID
			FROM Auction.AuctionedProducts p
			JOIN Auction.Bids b ON b.AuctionID = p.AuctionID
			WHERE p.Status = 'Active' AND p.ExpireDate < GETUTCDATE())
	
			UPDATE Auction.AuctionedProducts
			SET Status = 'Closed', EndDate = GETUTCDATE()
			WHERE Status = 'Active' AND ExpireDate < GETUTCDATE()
		COMMIT TRANSACTION
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0
		BEGIN
			PRINT XACT_STATE();
			ROLLBACK TRANSACTION;
		END
		PRINT ERROR_MESSAGE();
		THROW 50001,'An insert failed. The transaction was cancelled.', 0;
	END CATCH;		
END
GO