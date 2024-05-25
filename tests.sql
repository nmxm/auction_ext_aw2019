----LISTA de produtos available para Auction
SELECT ProductID, ListPrice, MakeFlag
FROM Production.Product
WHERE ProductID IN (
SELECT p.ProductID
FROM Production.Product p
JOIN Production.ProductInventory i ON p.ProductID = i.ProductID
WHERE SellEndDate IS NULL  AND DiscontinuedDate IS NULL AND i.LocationID = 6
GROUP BY p.ProductID
HAVING SUM(i.Quantity) > 0
)

--ProductID	ListPrice	MakeFlag
--ProductID	ListPrice	MakeFlag
--1	0,00	0
--2	0,00	0
--3	0,00	1
--4	0,00	0
--325	0,00	0
--326	0,00	0
--355	0,00	0
--356	0,00	0
--357	0,00	0
--358	0,00	0
--359	0,00	0
--360	0,00	0
--361	0,00	0
--362	0,00	0
--363	0,00	0
--364	0,00	0
--365	0,00	0
--366	0,00	0
--367	0,00	0
--368	0,00	0
--369	0,00	0
--370	0,00	0
--371	0,00	0
--372	0,00	0
--373	0,00	0
--374	0,00	0
--375	0,00	0
--376	0,00	0
--377	0,00	0
--378	0,00	0
--379	0,00	0
--380	0,00	0
--381	0,00	0
--382	0,00	0
--383	0,00	0
--384	0,00	0
--385	0,00	0
--386	0,00	0
--387	0,00	0
--388	0,00	0
--389	0,00	0
--390	0,00	0
--391	0,00	0
--392	0,00	0
--393	0,00	0
--394	0,00	0
--395	0,00	0
--396	0,00	0
--397	0,00	0
--402	0,00	0
--403	0,00	0
--404	0,00	0
--405	0,00	0
--406	0,00	0
--407	0,00	0
--408	0,00	0
--409	0,00	0
--410	0,00	0
--411	0,00	0
--412	0,00	0
--413	0,00	0
--414	0,00	0
--415	0,00	0
--416	0,00	0
--417	0,00	0
--418	0,00	0
--419	0,00	0
--420	0,00	0
--421	0,00	0
--422	0,00	0
--423	0,00	0
--424	0,00	0
--425	0,00	0
--426	0,00	0
--427	0,00	0
--428	0,00	0
--429	0,00	0
--430	0,00	0
--431	0,00	0
--432	0,00	0
--433	0,00	0
--434	0,00	0
--435	0,00	0
--436	0,00	0
--437	0,00	0
--438	0,00	0
--439	0,00	0
--440	0,00	0
--441	0,00	0
--442	0,00	0
--443	0,00	0
--444	0,00	0
--445	0,00	0
--446	0,00	0
--447	0,00	0
--448	0,00	0
--449	0,00	0
--450	0,00	0
--451	0,00	0
--452	0,00	0
--453	0,00	0
--454	0,00	0
--455	0,00	0
--456	0,00	0
--457	0,00	0
--458	0,00	0
--459	0,00	0
--460	0,00	0
--461	0,00	0
--462	0,00	0
--463	0,00	0
--464	0,00	0
--465	0,00	0
--466	0,00	0
--467	0,00	0
--468	0,00	0
--469	0,00	0
--470	0,00	0
--471	0,00	0
--472	0,00	0
--473	0,00	0
--474	0,00	0
--475	0,00	0
--489	0,00	0
--490	0,00	0
--491	0,00	0
--497	0,00	0
--504	0,00	0
--505	0,00	0
--506	0,00	0
--507	0,00	0
--508	0,00	0
--509	0,00	0
--510	0,00	0
--511	0,00	0
--512	0,00	0
--513	0,00	0
--514	133,34	1
--515	147,14	1
--516	196,92	1
--517	133,34	1
--518	147,14	1
--519	196,92	1
--520	133,34	1
--521	147,14	1
--522	196,92	1
--523	0,00	0
--524	0,00	0
--525	0,00	0
--526	0,00	0
--527	0,00	0
--528	0,00	0
--529	0,00	1
--530	0,00	0
--531	0,00	1
--532	0,00	1
--533	0,00	1
--534	0,00	1
--535	0,00	0
--679	0,00	0
--894	121,46	1
--907	106,50	0
--908	27,12	0
--909	39,14	0
--910	52,64	0
--911	27,12	0
--912	39,14	0
--913	52,64	0
--914	27,12	0
--915	39,14	0
--916	52,64	0
--921	4,99	0
--922	3,99	0
--923	4,99	0
--928	24,99	0
--929	29,99	0
--930	35,00	0
--931	21,49	0
--932	24,99	0
--933	32,60	0
--934	28,99	0
--935	40,49	0
--936	62,09	0
--937	80,99	0
--938	40,49	0
--939	62,09	0
--940	80,99	0
--941	80,99	0
--994	53,99	1
--995	101,24	1
--996	121,49	1


--test store procedure 1
EXEC Auction.uspAddProductToAuction @ProductID = 2; --- No error


-- Test adding a product that is not commecrialized
EXEC Auction.uspAddProductToAuction @ProductID = 709; -- should throw error

-- Test adding a product that is already in the auction
EXEC Auction.uspAddProductToAuction @ProductID = 2; -- should throw error

-- Test adding a product to the auction with @ExpireDate out of lower than the start of auction period
EXEC Auction.uspAddProductToAuction @ProductID = 518, @ExpireDate = '2023-08-05', @InitialBidPrice = 100;

-- Test adding a product to the auction with @ExpireDate out of lower than the start of auction period
EXEC Auction.uspAddProductToAuction @ProductID = 996, @ExpireDate = '2023-08-05', @InitialBidPrice = 100; --error should be greater than 2023-11-13

-- Test adding a product to the auction with @ExpireDate out of auction period
EXEC Auction.uspAddProductToAuction @ProductID = 907, @ExpireDate = '2023-11-28', @InitialBidPrice = 100; --assign limit value to @ExpireDate

-- Test adding a product to the auction with @InitialBidPrice higher than ListPrice
EXEC Auction.uspAddProductToAuction @ProductID = 996, @ExpireDate = '2023-11-20', @InitialBidPrice = 150; --correct the @InitialBidPrice to the ListPrice - 0,05 to allow one bid

-- Test adding a product to the auction with @InitialBidPrice lower than ListPrice*50%
EXEC Auction.uspAddProductToAuction @ProductID = 995, @ExpireDate = '2023-11-20', @InitialBidPrice = 50; --correct the @InitialBidPrice to the mininum allowed


-- uspTryBidProduct
-- Test trying to bid on a product with no existing bids
EXEC Auction.uspTryBidProduct @ProductID = 995, @CustomerID = 1;

--changing clock to bing 27-11-2023
EXEC Auction.uspTryBidProduct @ProductID = 907, @CustomerID = 1;

-- Test trying to bid on a product with an bid who exceeds the product maximun value
EXEC Auction.uspTryBidProduct @ProductID = 995, @CustomerID = 2, @BidAmount = 4000000; -- should throw error

-- Test trying to bid on a product with a valid bid amount
EXEC Auction.uspTryBidProduct @ProductID = 995, @CustomerID = 3, @BidAmount = 40; --low value

-- Test trying to bid on a product with a valid bid amount greater than the initial bid price
EXEC Auction.uspTryBidProduct @ProductID = 995, @CustomerID = 4, @BidAmount = 80;

-- Test trying to bid on a product with a valid bid amount less than the initial bid price
EXEC Auction.uspTryBidProduct @ProductID = 518, @CustomerID = 4, @BidAmount = 2; -- should throw error'

-- Test trying to bid on a product with a valid bid amount greater than the initial bid price
EXEC Auction.uspTryBidProduct @ProductID = 518, @CustomerID = 4, @BidAmount = 4000; -- should throw error'

--Test canceling one product already in auctionID
EXEC Auction.upsRemoveProductFromAuction 996 --

--Test canceling one product already in auctionID
EXEC Auction.upsRemoveProductFromAuction 500

EXEC Auction.upsListBidOffersHistory 1,"2023-11-11", "2023-11-30" -- should show nothing

EXEC Auction.upsListBidOffersHistory 1,"2023-11-11", "2023-11-30" -- should show transactions

EXEC Auction.upsListBidOffersHistory 100,"2023-11-11", "2023-11-30" -- should throw Customer error

--EXEC Auction.uspUpdateAuctionStatus


select * from Auction.Threshold

SELECT * from Auction.AuctionedProducts

SELECT * from Auction.Bids