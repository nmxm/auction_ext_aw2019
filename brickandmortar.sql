SELECT TOP 2 a.City, SUM(sod.UnitPrice - prod.StandardCost) AS TotalGrossMargin -- Selecting the top 2 cities where our individual customers are located by sum of TotalGrossMargin
from Sales.SalesOrderHeader soh
JOIN Sales.SalesOrderDetail sod ON sod.SalesOrderID = soh.SalesOrderID
JOIN Sales.Customer c ON c.CustomerID = soh.CustomerID
JOIN Person.Person p ON p.BusinessEntityID = c.PersonID
JOIN Person.BusinessEntityAddress bae ON bae.BusinessEntityID = p.BusinessEntityID
JOIN Person.Address a ON a.AddressID = bae.AddressID
JOIN Person.StateProvince sp ON sp.StateProvinceID = a.StateProvinceID
JOIN Production.Product prod ON prod.ProductID = sod.ProductID
WHERE sp.CountryRegionCode = 'US' AND OrderDate >= DATEADD(year, -1, (SELECT MAX(OrderDate) FROM Sales.SalesOrderHeader)) AND prod.SellEndDate IS NULL AND soh.Status in (1,2,5)  -- Top 2 cities considering only US cities, ordered active products in the last 12 months excl. cancelled and rejected orders.
AND a.City NOT IN 
( 
SELECT TOP 30 a.City
from Sales.SalesOrderHeader soh
JOIN Sales.Customer c ON c.CustomerID = soh.CustomerID
JOIN Sales.Store s ON s.BusinessEntityID = c.StoreID
JOIN Person.BusinessEntityAddress bae ON bae.BusinessEntityID = s.BusinessEntityID
JOIN Person.Address a ON a.AddressID = bae.AddressID
JOIN Person.StateProvince sp ON sp.StateProvinceID = a.StateProvinceID
WHERE sp.CountryRegionCode = 'US' AND soh.Status in (2,5) -- Considering only StoreContacts in US
GROUP BY s.BusinessEntityID, a.City
ORDER BY SUM(soh.SubTotal) DESC -- Ordering by Sales
) -- Making sure the cities where our TOP30 store contacts are located are excluded 
GROUP BY a.City
ORDER BY TotalGrossMargin DESC