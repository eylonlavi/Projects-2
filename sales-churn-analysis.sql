/* =====================================================================
   Sales & Customer Churn Analysis
   Database: WideWorldImporters (SQL Server)
   By Eylon Lavi

   John Bryce Data Analyst program – Project 2 (SQL Data Analysis).
   10 business-intelligence queries on sales, customers, products and
   suppliers, plus a customer-level churn extension at the end.
   Techniques: CTEs, window functions (LAG, RANK, DENSE_RANK,
   ROW_NUMBER, running SUM), PIVOT, STRING_AGG, UNION ALL.

   Definitions used in the assignment:
   - "Profit" = ExtendedPrice - TaxAmount, i.e. UnitPrice * Quantity.
   - Dates are based on InvoiceDate unless stated otherwise.
   ===================================================================== */

USE WideWorldImporters

--1
/* Yearly sales, linear yearly income and growth rate.
   Linear yearly income = average monthly income * 12, so partial years
   (2016) can be compared with full years. Growth rate compares each
   year's linear income with the previous year. */

WITH yearly_income
AS
(SELECT YEAR(InvoiceDate) AS InvoiceYear,SUM(OL.UnitPrice*OL.PickedQuantity) AS IncomePerYear,
MAX(MONTH(InvoiceDate)) AS NumberOfDistinctMonths
FROM Sales.Invoices I JOIN Sales.OrderLines OL
ON I.OrderID=OL.OrderID
GROUP BY YEAR(InvoiceDate)),
linear_income AS
(SELECT *,ROUND((IncomePerYear/NumberOfDistinctMonths)*12,2) AS YearlyLinearIncome
FROM yearly_income),
growth AS
(SELECT *,(YearlyLinearIncome-LAG(YearlyLinearIncome)OVER(ORDER BY InvoiceYear))
/LAG(YearlyLinearIncome)OVER(ORDER BY InvoiceYear)*100 AS GrowthRate
FROM linear_income)
SELECT InvoiceYear,FORMAT(IncomePerYear,'#,#.00') AS IncomePerYear,NumberOfDistinctMonths,
FORMAT(YearlyLinearIncome,'#,#.00') AS YearlyLinearIncome,
FORMAT(GrowthRate,'#,#.00') AS GrowthRate
FROM growth











GO

--2
/* Top 5 customers by net income in every quarter of every year.
   Net income per customer is summed per quarter, then ranked within
   each quarter with DENSE_RANK. */
WITH invoice_lines
AS
(SELECT I.InvoiceDate,YEAR(I.InvoiceDate) AS TheYear,DATEPART(Q,I.InvoiceDate) AS TheQuarter
,C.CustomerName,IL.UnitPrice*IL.Quantity AS CustomerPrice
 FROM Sales.Invoices I JOIN Sales.Customers C
ON I.CustomerID=C.CustomerID
	JOIN Sales.InvoiceLines IL
ON I.InvoiceID=IL.InvoiceID),
quarterly_income AS
(SELECT TheYear,TheQuarter ,CustomerName,
SUM(invoice_lines.CustomerPrice)
AS IncomePerQuarterYear
FROM invoice_lines
GROUP BY TheYear,TheQuarter ,invoice_lines.CustomerName),
ranked AS
(SELECT TheYear,TheQuarter ,CustomerName,IncomePerQuarterYear,
DENSE_RANK() OVER(PARTITION BY TheYear,TheQuarter ORDER BY quarterly_income.IncomePerQuarterYear DESC) AS DNR
FROM quarterly_income)
SELECT *
FROM ranked
WHERE DNR<=5

GO

--3
/* Top 10 products by total profit (UnitPrice * quantity sold),
   with the product ID and name. */
WITH product_lines
AS
(SELECT S.StockItemID,S.StockItemName,O.UnitPrice*O.PickedQuantity AS LineProfit
FROM Warehouse.StockItems S JOIN Sales.OrderLines O
ON S.StockItemID=O.StockItemID)
SELECT TOP 10 StockItemID,StockItemName,SUM(LineProfit) AS TotalProfit
FROM product_lines
GROUP BY StockItemID,StockItemName
ORDER BY TotalProfit DESC

GO


--4
/* Valid stock items ranked by nominal profit per unit
   (recommended retail price minus unit price), with a row number
   and a dense rank. */
WITH product_margin
AS
(SELECT SI.StockItemID,SI.StockItemName,SI.UnitPrice,SI.RecommendedRetailPrice,
SI.RecommendedRetailPrice-SI.UnitPrice AS NominalProductProfit
FROM Warehouse.StockItems SI)
SELECT ROW_NUMBER() OVER(ORDER BY NominalProductProfit DESC) AS Rn,product_margin.*,
DENSE_RANK() OVER(ORDER BY NominalProductProfit DESC) AS DNR
FROM product_margin
ORDER BY NominalProductProfit DESC


--5
/* Product catalog per supplier, in one row per supplier.
   Each product appears as "ID name", separated by '/,'. */
SELECT CONCAT_WS(' - ',S.SupplierID,S.SupplierName) AS SupplierDetails,
STRING_AGG(CONCAT_WS(' ',SI.StockItemID,SI.SearchDetails),'/,') AS ProductDetails
FROM Purchasing.Suppliers S JOIN Warehouse.StockItems SI
ON S.SupplierID=SI.SupplierID
GROUP BY  S.SupplierID,S.SupplierName
ORDER BY S.SupplierID


GO


--6
/* Top 5 customers by total extended price (including tax),
   with their city, country, continent and region. */
WITH customer_totals
AS
(SELECT TOP 5 CU.CustomerID,CI.CityName,COU.CountryName,COU.Continent,COU.Region
,SUM(OL.UnitPrice*OL.PickedQuantity*(1+(OL.TaxRate/100))) AS TotalExtendedPrice
FROM Sales.Customers CU JOIN Application.Cities CI
ON CU.DeliveryCityID=CI.CityID
	JOIN Application.StateProvinces SP
ON CI.StateProvinceID=SP.StateProvinceID
	JOIN Application.Countries COU
ON COU.CountryID=SP.CountryID
	JOIN Sales.Invoices I
ON I.CustomerID=CU.CustomerID
	JOIN Sales.OrderLines OL
ON OL.OrderID=I.OrderID
GROUP BY CU.CustomerID,CI.CityName,COU.CountryName,COU.Continent,COU.Region
ORDER BY TotalExtendedPrice DESC)
SELECT CustomerID,CityName,CountryName,Continent,Region,
FORMAT(TotalExtendedPrice,'#,#.00') AS TotalExtendedPrice
FROM customer_totals


GO


--7
/* Monthly and cumulative sales per year, with a "Grand Total" row
   after the last month of each year. The Grand Total row is the
   cumulative total of the year's last month, so the query works for
   any number of years. */
WITH monthly_sales
AS
(SELECT YEAR(I.InvoiceDate) AS InvoiceYear,MONTH(I.InvoiceDate) AS InvoiceMonth
,SUM(OL.Quantity*OL.UnitPrice) AS MonthlyTotal
FROM Sales.Invoices I  JOIN Sales.OrderLines OL
ON I.OrderID=OL.OrderID
GROUP BY YEAR(I.InvoiceDate),MONTH(I.InvoiceDate)),
running AS
(SELECT *
,SUM(MonthlyTotal) OVER(PARTITION BY InvoiceYear ORDER BY InvoiceYear,InvoiceMonth) AS CumulativeTotal
FROM monthly_sales),
report AS
(SELECT InvoiceYear,CAST(InvoiceMonth AS VARCHAR)AS InvoiceMonth,InvoiceMonth AS SortOrder,MonthlyTotal,CumulativeTotal
FROM running
UNION ALL
SELECT InvoiceYear,'Grand Total' AS InvoiceMonth,13 AS SortOrder
,CumulativeTotal AS MonthlyTotal,CumulativeTotal
FROM running R
WHERE InvoiceMonth=(SELECT MAX(InvoiceMonth) FROM running WHERE InvoiceYear=R.InvoiceYear))
SELECT InvoiceYear,InvoiceMonth,FORMAT(MonthlyTotal,'#,#.00')AS MonthlyTotal,
FORMAT(CumulativeTotal,'#,#.00') AS CumulativeTotal
FROM report
ORDER BY InvoiceYear,SortOrder





--8
/* Number of orders per month in each year, as a PIVOT matrix
   (months in rows, years in columns). */
SELECT OrderMonth,[2013],[2014],[2015],[2016]
FROM(SELECT YEAR(OrderDate) AS OrderYear, MONTH(OrderDate) AS OrderMonth,OrderID
     FROM Sales.Orders) T
PIVOT(COUNT(OrderID) FOR OrderYear IN([2013],[2014],[2015],[2016])) AS PVT
ORDER BY OrderMonth


GO


--9
/* Potential churn – order level, as required in the assignment.
   A customer is "Potential Churn" when the days since their last order
   (relative to the last order in the table) exceed twice their average
   number of days between orders. */
WITH order_history
AS
(SELECT C.CustomerID,C.CustomerName,O.OrderDate,
LAG(O.OrderDate) OVER(PARTITION BY C.CustomerID ORDER BY OrderDate)AS PreviousOrderDate
FROM Sales.Customers C JOIN Sales.Orders O
ON C.CustomerID=O.CustomerID),
customer_metrics AS
(SELECT *,
AVG(DATEDIFF(DD,PreviousOrderDate,OrderDate)) OVER (PARTITION BY CustomerID) AS AvgDaysBetweenOrders,
MAX(OrderDate) OVER(PARTITION BY CustomerID) AS LastCustOrderDate,
MAX(OrderDate) OVER() AS LastOrderDateAll
FROM order_history),
recency AS
(SELECT *,
DATEDIFF(DD,LastCustOrderDate,LastOrderDateAll) AS DaysSinceLastOrder
FROM customer_metrics)
SELECT *,
CASE WHEN DaysSinceLastOrder>AvgDaysBetweenOrders*2 THEN 'Potential Churn'
ELSE 'Active'
END AS CustomerStatus
FROM recency


GO


--10
/* Business risk by customer category.
   All "Tailspin" branches count as one customer, and so do all
   "Wingtip" branches. Shows each category's share of all customers;
   the category with the highest share carries the highest risk. */
WITH unique_customers
AS
(SELECT TOP 1 C.CustomerName,CC.CustomerCategoryID,CC.CustomerCategoryName
FROM Sales.Customers C JOIN Sales.CustomerCategories CC
ON C.CustomerCategoryID=CC.CustomerCategoryID
WHERE CustomerName LIKE 'Tailspin%'
UNION
SELECT TOP 1 C.CustomerName,CC.CustomerCategoryID,CC.CustomerCategoryName
FROM Sales.Customers C JOIN Sales.CustomerCategories CC
ON C.CustomerCategoryID=CC.CustomerCategoryID
WHERE CustomerName LIKE 'Wingtip%'
UNION
SELECT C.CustomerName,CC.CustomerCategoryID,CC.CustomerCategoryName
FROM Sales.Customers C JOIN Sales.CustomerCategories CC
ON C.CustomerCategoryID=CC.CustomerCategoryID
WHERE C.CustomerName NOT LIKE 'Tailspin%'
AND C.CustomerName NOT LIKE 'Wingtip%'),
category_counts AS
(SELECT CustomerCategoryName,COUNT(CustomerName) AS CustomerCount
FROM unique_customers
GROUP BY CustomerCategoryName),
with_total AS
(SELECT *,SUM(CustomerCount) OVER() AS TotalCustCount
FROM category_counts)
SELECT *, CONCAT(CAST(CustomerCount AS money)/CAST(TotalCustCount AS money)*100,'%')
AS DistributionFactor
FROM with_total


GO


/* =====================================================================
   EXTENSION (beyond the assignment) – churn at customer level
   Q9 returns one row per order, as the assignment asked. This version
   returns one row per customer, gives customers with a single order
   their own status, and ends with a summary per status.
   AVG ignores the NULL gap of each customer's first order, and * 1.0
   keeps the average from being rounded to a whole number.
   ===================================================================== */
WITH order_gaps
AS
(SELECT C.CustomerID,C.CustomerName,O.OrderDate,
DATEDIFF(DD,LAG(O.OrderDate) OVER(PARTITION BY C.CustomerID ORDER BY O.OrderDate,O.OrderID),O.OrderDate) AS DaysSincePrev
FROM Sales.Customers C JOIN Sales.Orders O
ON C.CustomerID=O.CustomerID),
customer_stats AS
(SELECT CustomerID,CustomerName,COUNT(*) AS TotalOrders,
AVG(DaysSincePrev*1.0) AS AvgDaysBetweenOrders,
MAX(OrderDate) AS LastOrderDate
FROM order_gaps
GROUP BY CustomerID,CustomerName),
customer_status AS
(SELECT *,
DATEDIFF(DD,LastOrderDate,(SELECT MAX(OrderDate) FROM Sales.Orders)) AS DaysSinceLastOrder
FROM customer_stats)
SELECT CustomerID,CustomerName,TotalOrders,ROUND(AvgDaysBetweenOrders,1) AS AvgDaysBetweenOrders,
LastOrderDate,DaysSinceLastOrder,
CASE WHEN TotalOrders<2 THEN 'Not enough history'
WHEN DaysSinceLastOrder>AvgDaysBetweenOrders*2 THEN 'Potential Churn'
ELSE 'Active'
END AS CustomerStatus
FROM customer_status
ORDER BY DaysSinceLastOrder DESC


GO


--Summary: number and share of customers in each status
WITH order_gaps
AS
(SELECT C.CustomerID,O.OrderDate,
DATEDIFF(DD,LAG(O.OrderDate) OVER(PARTITION BY C.CustomerID ORDER BY O.OrderDate,O.OrderID),O.OrderDate) AS DaysSincePrev
FROM Sales.Customers C JOIN Sales.Orders O
ON C.CustomerID=O.CustomerID),
customer_stats AS
(SELECT CustomerID,COUNT(*) AS TotalOrders,
AVG(DaysSincePrev*1.0) AS AvgDaysBetweenOrders,
DATEDIFF(DD,MAX(OrderDate),(SELECT MAX(OrderDate) FROM Sales.Orders)) AS DaysSinceLastOrder
FROM order_gaps
GROUP BY CustomerID),
labeled AS
(SELECT CASE WHEN TotalOrders<2 THEN 'Not enough history'
WHEN DaysSinceLastOrder>AvgDaysBetweenOrders*2 THEN 'Potential Churn'
ELSE 'Active'
END AS CustomerStatus
FROM customer_stats)
SELECT CustomerStatus,COUNT(*) AS Customers,
CONCAT(CAST(100.0*COUNT(*)/SUM(COUNT(*)) OVER() AS DECIMAL(5,1)),'%') AS PctOfCustomers
FROM labeled
GROUP BY CustomerStatus
ORDER BY Customers DESC
