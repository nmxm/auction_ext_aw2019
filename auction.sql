-- Threshold Reqs:
-- T-Req 1: By default, users can only increase bids by 5 cents (minimum increase bid);
-- T-Req 2: These thresholds should be easily configurable within a table so there is no need to change the database;
-- T-Req 3: These thresholds should be global and not per product/category;
-- T-Req 4: This campaign takes place during the last two weeks of November including Black Friday;

-- Auction Reqs:
-- A-Req 1: Only products that are currently commercialized (both SellEndDate and DiscontinuedDate values not set);
-- A-Req 2: Only one item for each ProductID can be simultaneously enlisted as an auction;

-- Bids Reqs:
-- B-Req 1: Maximum bid limit that is equal to initial product listed price
-- B-Req 2: Initial bid price for products that are not manufactured in-house (MakeFlag value is 0) should be 75% of listed price;
-- B-Req 3: Initial bid price for products that are manufactured in-house (MakeFlag value is 1) should be 50% of listed price;

-- Technical Reqs:
-- Tech-Req 1: All new database objects should be created within Auction schema;
-- Tech-Req 2: T-SQL script should also pre-populate any required configuration tables with default values;
-- Tech-Req 3: Being idempotent, this population should be just performed once no matter how many times t-SQL script is executed;
-- Tech-Req 4: All stored procedures should have proper error/exception handling mechanism;

USE AdventureWorks
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'Auction')
    BEGIN
        EXEC('CREATE SCHEMA Auction')
    END
GO

-- AuctionedProducts: This table stores information about the products that are being auctioned.
    -- It contains columns such as AuctionID (primary key), ProductID, StartDate, ExpireDate, EndDate, InitialBidPrice, Status and WinnerBid.
    -- AuctionID is an identity column and serves as the primary key of this table.
    -- ProductID is a FK that references the ProductID column of the Production.Product table,
    -- maintaining data integrity and consistency in the database adding only existing Products.
    -- StartDate and ExpireDate columns specify the start and end time of the auction.
    -- The EndDate column stores the UTC date when the auction is closed or canceled.
    -- The InitialBidPrice column specifies the minimum bid value for the first bid.
    -- The Status column indicates the current status of the auction, which can be "Active", "Closed", or "Cancelled".
    -- The WinnerBid column stores the BidID of the winning bid when the auction is closed.
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

-- Bids: This table stores information about all valid bids that are placed on auctioned products.
    -- It contains columns such as BidID (primary key), CustomerID, AuctionID, BidAmount and BidDate.
    -- BidID is an identity column and serves as the primary key of this table.
    -- CustomerID is a foreign key that references the CustomerID column of the Sales.Customer table
    -- maintaining data integrity and consistency in the database adding only existing Customers.
    -- AuctionID is a foreign key that references the AuctionID column of the AuctionedProducts table.
    -- maintaining data integrity and consistency in the database adding only existing AuctionedProducts.
    -- BidAmount specifies the amount of the bid, and BidDate stores the UTC date and time when the bid was placed.
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

		ALTER TABLE Auction.AuctionedProducts
			ADD CONSTRAINT FK_LastBidID
				FOREIGN KEY (WinnerBid) REFERENCES Auction.Bids(BidID);

		CREATE INDEX IX_Bids_AuctionId_BidAmount ON Auction.Bids (AuctionID,BidAmount)
	END;
GO

-- Threshold: This table stores global configuration for bids and auctions.
    -- It contains columns such as ThresholdID (primary key), MinimumIncreaseBid, MaxAuctionPrice, MinStartDate, and MaxExpireDate.
    -- ThresholdID is an identity column and serves as the primary key of this table.
    -- MinimumIncreaseBid specifies the minimum amount by which a bid must increase from the previous bid.
    -- MaxAuctionPrice specifies the maximum price that can be reached in an auction, as a percentage of the productS value.
    -- MinStartDate and MaxExpireDate specify the range of valid start and end times for auctions.
    -- The MaxAuctionPrice column has a check constraint that ensures its value is between 0 and 1.
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

        -- The purpose of this INSERT statement is to set the initial values for the global configuration of the threshold
        -- values that are used to determine the valid bids and auctions,takes place during the last two weeks of November including Black Friday .
		INSERT INTO Auction.Threshold (MinimumIncreaseBid, MaxAuctionPrice ,MinStartDate, MaxExpireDate) VALUES (0.05, 1, '2023-11-13 00:00:00', '2023-11-26 23:59:59');
	END
GO

    -- Stored procedure name: uspAddProductToAuction
    -- 1. Check if the product exists, is currently on sale, and has stock available to be cleared. If the product fails this check, the procedure raises an error and stops execution.
    -- 2. Check if the product is already added to an active auction. If so, the procedure raises an error and stops execution.
    -- 3. Check that the insertion date in UTC time is before the auction end limit. If the insertion date is after the limit, the procedure raises an error and stops execution.
    -- 4. Check that the expiration date for the auction is within the valid date range. If the expiration date is outside this range, the procedure raises an error and stops execution.
    -- 5. If an expiration date is not specified, set the expiration date to one week after the start date.
    -- 6. Check if the initial bid price for the product is valid. If the initial bid price is not specified, set it to the minimum allowed value.
    -- For products that are not manufactured in-house, set the initial bid price to 75% of the listed price. For products that are manufactured in-house, set the initial bid price to 50% of the listed price.
    -- 8. <<NEED TO CHECK>> If the initial bid price is outside the valid bid range, set it to the maximum allowed value. If the initial bid price is too low, set it to the minimum allowed value.
    -- 9. Insert the product into the AuctionedProducts table with the status set to "Active"
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

	SELECT @MinStartDate = MinStartDate,
	       @MaxAuctionPrice = MaxAuctionPrice,
	       @MaxExpireDate = MaxExpireDate,
	       @MinimumIncreaseBid = MinimumIncreaseBid
	FROM Auction.Threshold

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
					SET @msgtext = CONCAT('Expire date should be greater than ',@MinStartDate)
					RAISERROR (@msgtext, 16, 1)
					RETURN
				END
			IF @ExpireDate < GETUTCDATE()
				BEGIN
					RAISERROR ('Expire date should be greater than the current date!', 16, 1)
					RETURN
				END
		END
	ELSE
		BEGIN
			SET @ExpireDate = DATEADD(d,7,@StartDate)
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

-- Stored procedure name: uspTryBidProduct
-- 1. The stored procedure checks to make sure that the @CustomerID provided exists in the Sales.Customer table. If the customer does not exist, an error message is raised and the procedure terminates.
-- 2. The stored procedure checks whether the product specified by the @ProductID is currently active in an auction by querying the Auction.AuctionedProducts table. If the product is not being auctioned or if the auction has expired, an error message is raised and the procedure terminates.
-- 3. If the auction is active but it is too early to bid, the stored procedure will raise an error message and terminate.
-- 4. The stored procedure checks whether the @BidAmount is specified by the customer
    -- If the @BidAmount is not provided by the customer:
        -- The stored procedure will determine the initial bid price or the highest bid amount so far and add the minimum increase bid amount specified in the Auction.Threshold table to it.
    -- If the @BidAmount is provided:
        -- The stored procedure will check that the bid amount is greater than or equal to the current highest bid amount plus the minimum increase bid amount.
-- 5. The stored procedure checks whether the @BidAmount specified is less than or equal to the maximum bid price, which is calculated as the products list price multiplied by a maximum auction price specified in the Auction.Threshold table.
-- 6. If all of the above checks pass, the stored procedure inserts a new row into the Auction.Bids table with the specified @CustomerID, @AuctionID, @BidAmount, and the current datetime.
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

--Check BidAmount valid
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
			IF  @MaxBid IS NULL
				BEGIN
					IF @BidAmount < @InitialBidPrice
					RAISERROR('Bid too Low!',16,1)
					RETURN
				END
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

-- Stored procedure name: upsRemoveProductFromAuction
-- 1. That removes a product from an ongoing auction. It takes an input parameter called @ProductID, which is an integer value representing the ID of the product to be removed.
-- 2. The procedure first checks if the product with the specified ID is currently in an active auction by querying the AuctionedProducts table. If the product is not found in an active auction, the procedure raises an error and exits.
-- 3. If the product is found in an active auction, the procedure updates the Status and EndDate columns of the corresponding row in the AuctionedProducts table. The Status is changed to 'Cancelled', indicating that the auction for the product has been cancelled, and the EndDate is set to the current UTC date and time.
-- 4. The procedure does not return any result sets, but it may raise an error if the input parameter is invalid or if there is a problem with updating the database.
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

-- Stored procedure name: upsListBidOffersHistory
-- 1. The procedure takes four input parameters: @CustomerID, @StartTime, @EndTime, and @Active.
-- 2. The procedure first checks if the specified @CustomerID has ever placed a bid on any product in the Auction.Bids table.
    -- If there are no records in the Auction.Bids table with the specified @CustomerID, the procedure raises an error message with severity level 16 and returns control to the calling program without executing any further code.
-- 3. If the @Active parameter is set to 1, the procedure retrieves the bid offers history for the specified @CustomerID within the specified date range where the corresponding auctioned product is still active.
-- 4. If the @Active parameter is not set to 1, the procedure retrieves the bid offers history for the specified @CustomerID within the specified date range, regardless of the status of the corresponding auctioned product.
-- 5. The procedure returns the retrieved bid offers history.
CREATE OR ALTER PROCEDURE Auction.upsListBidOffersHistory(@CustomerID INT, @StartTime datetime, @EndTime datetime, @Active bit = 1)
AS
BEGIN
    IF NOT EXISTS(SELECT CustomerID FROM Auction.Bids WHERE CustomerID = @CustomerID)
        BEGIN
            RAISERROR ('The inserted Customer never bid a product!', 16, 1);
            RETURN;
        END

    IF @Active = 1
        BEGIN
            SELECT b.BidID, b.AuctionID, a.ProductID, b.BidAmount, b.BidDate
            FROM Auction.Bids as b
                     JOIN Auction.AuctionedProducts as a ON b.AuctionID = a.AuctionID
            WHERE b.CustomerID = @CustomerID AND b.BidDate >= @StartTime AND b.BidDate <= @EndTime AND a.Status = 'Active'
        END
    ELSE
        BEGIN
            SELECT b.BidID, b.AuctionID, a.ProductID, b.BidAmount, b.BidDate
            FROM Auction.Bids as b
                     JOIN Auction.AuctionedProducts as a ON b.AuctionID = a.AuctionID
            WHERE b.CustomerID = @CustomerID AND b.BidDate >= @StartTime AND b.BidDate <= @EndTime
        END
END
GO

-- Stored procedure name: uspUpdateAuctionStatus
-- 1. That updates the status of an active auction to "Closed" and sets the EndDate of the auction to the current UTC date and time. It also sets the WinnerBid to the BidID of the customer who placed the highest bid in the auction.
-- 2. The procedure first starts a transaction using the BEGIN TRANSACTION statement, and then executes an UPDATE statement to change the status of the active auctioned products that have expired based on the ExpireDate field. The subquery in the UPDATE statement finds the highest bid placed by a customer in the auction and sets the WinnerBid field of the corresponding auction product to the BidID of the winning bid.
-- 3. Check the transaction
    -- If the UPDATE statement is successful, the transaction is committed using the COMMIT TRANSACTION statement.
    -- If an error occurs during the transaction, the CATCH block is executed, and the transaction is rolled back using the ROLLBACK TRANSACTION statement. The procedure also prints the error message and throws a custom error message using the THROW statement.
CREATE OR ALTER PROCEDURE Auction.uspUpdateAuctionStatus
AS
BEGIN
	BEGIN TRY
		BEGIN TRANSACTION
			UPDATE Auction.AuctionedProducts
			SET Status = 'Closed',EndDate = GETUTCDATE(),
				WinnerBid = (
					SELECT TOP 1 Auction.Bids.BidID
					FROM Auction.Bids
					WHERE Auction.Bids.AuctionID = Auction.AuctionedProducts.AuctionID
					ORDER BY BidAmount DESC
				)
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