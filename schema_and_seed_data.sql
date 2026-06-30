-- ============================================================
-- PROJECT 4: Supply Chain & Delivery Lead Time Optimization
-- Phase 1: Database Schema + Seed Data
-- Tool: SQL Server (SSMS 22) | Syntax: T-SQL
-- Analyst: Bhuvaneshwari Vijay | June 2026
-- ============================================================
-- HOW TO RUN:
--   1. Open SSMS 22
--   2. Connect to your local SQL Server instance
--   3. Run this entire file (F5 or Execute)
--   4. A new database called [SupplyChainDB] will be created
-- ============================================================


-- ── STEP 0: Create & use the database ──────────────────────
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'SupplyChainDB')
    CREATE DATABASE SupplyChainDB;
GO

USE SupplyChainDB;
GO


-- ── STEP 1: Drop tables if re-running ──────────────────────
IF OBJECT_ID('dbo.Shipments', 'U') IS NOT NULL DROP TABLE dbo.Shipments;
IF OBJECT_ID('dbo.Orders',    'U') IS NOT NULL DROP TABLE dbo.Orders;
IF OBJECT_ID('dbo.Warehouses','U') IS NOT NULL DROP TABLE dbo.Warehouses;
IF OBJECT_ID('dbo.DeliveryZones','U') IS NOT NULL DROP TABLE dbo.DeliveryZones;
GO


-- ============================================================
-- TABLE 1: DeliveryZones
-- What it stores: India courier zones with SLA targets
-- NE India zones have higher SLA targets (geography/infra)
-- ============================================================
CREATE TABLE dbo.DeliveryZones (
    ZoneID          INT PRIMARY KEY,
    ZoneName        VARCHAR(50)  NOT NULL,
    Region          VARCHAR(50)  NOT NULL,   -- Metro / Tier2 / NE India / Remote
    SLA_Days        INT          NOT NULL,   -- Delhivery published target (days)
    IsNEIndia       BIT          NOT NULL DEFAULT 0
);
GO

INSERT INTO dbo.DeliveryZones (ZoneID, ZoneName, Region, SLA_Days, IsNEIndia) VALUES
(1,  'Mumbai Metro',       'Metro',    2, 0),
(2,  'Delhi Metro',        'Metro',    2, 0),
(3,  'Bengaluru Metro',    'Metro',    2, 0),
(4,  'Chennai Metro',      'Metro',    2, 0),
(5,  'Hyderabad Metro',    'Metro',    2, 0),
(6,  'Pune Tier2',         'Tier2',    3, 0),
(7,  'Ahmedabad Tier2',    'Tier2',    3, 0),
(8,  'Jaipur Tier2',       'Tier2',    4, 0),
(9,  'Lucknow Tier2',      'Tier2',    4, 0),
(10, 'Bhopal Tier2',       'Tier2',    4, 0),
(11, 'Guwahati NE',        'NE India', 7, 1),
(12, 'Shillong NE',        'NE India', 7, 1),
(13, 'Imphal NE',          'NE India', 8, 1),
(14, 'Agartala NE',        'NE India', 8, 1),
(15, 'Itanagar NE',        'NE India', 9, 1),
(16, 'Kohima NE',          'NE India', 9, 1),
(17, 'Aizawl NE',          'NE India', 9, 1),
(18, 'Gangtok NE',         'NE India', 7, 1),
(19, 'Dibrugarh NE',       'NE India', 8, 1),
(20, 'Silchar NE',         'NE India', 8, 1);
GO


-- ============================================================
-- TABLE 2: Warehouses
-- What it stores: Origin warehouses across India
-- ProcessingTime_Avg = baseline hours to process an order
-- ============================================================
CREATE TABLE dbo.Warehouses (
    WarehouseID     INT PRIMARY KEY,
    WarehouseName   VARCHAR(100) NOT NULL,
    City            VARCHAR(50)  NOT NULL,
    State           VARCHAR(50)  NOT NULL,
    Region          VARCHAR(50)  NOT NULL,
    ProcessingTime_Avg_Hrs DECIMAL(5,2) NOT NULL  -- baseline avg; NE-bound orders will be higher
);
GO

INSERT INTO dbo.Warehouses (WarehouseID, WarehouseName, City, State, Region, ProcessingTime_Avg_Hrs) VALUES
(1,  'WH-Mumbai-Central',    'Mumbai',    'Maharashtra',   'West',   4.5),
(2,  'WH-Delhi-North',       'Delhi',     'Delhi',         'North',  5.0),
(3,  'WH-Bengaluru-South',   'Bengaluru', 'Karnataka',     'South',  4.0),
(4,  'WH-Kolkata-East',      'Kolkata',   'West Bengal',   'East',   6.5),   -- Key NE gateway
(5,  'WH-Chennai-South',     'Chennai',   'Tamil Nadu',    'South',  4.2),
(6,  'WH-Guwahati-NE',       'Guwahati',  'Assam',         'NE',     9.5),   -- NE hub, high processing
(7,  'WH-Hyderabad-Central', 'Hyderabad', 'Telangana',     'South',  4.8),
(8,  'WH-Pune-West',         'Pune',      'Maharashtra',   'West',   5.1),
(9,  'WH-Siliguri-East',     'Siliguri',  'West Bengal',   'East',   7.2),   -- NE entry point
(10, 'WH-Guwahati-NE2',      'Guwahati',  'Assam',         'NE',    10.8);   -- Overflow NE hub
GO


-- ============================================================
-- TABLE 3: Orders
-- What it stores: Customer orders with timestamps
-- order_placed_at → warehouse_received_at → shipped_at
-- ============================================================
CREATE TABLE dbo.Orders (
    OrderID             INT PRIMARY KEY,
    CustomerName        VARCHAR(100) NOT NULL,
    OrderPlacedAt       DATETIME     NOT NULL,
    WarehouseID         INT          NOT NULL,
    ZoneID              INT          NOT NULL,
    ProductCategory     VARCHAR(50)  NOT NULL,
    OrderValue_INR      DECIMAL(10,2)NOT NULL,
    CONSTRAINT FK_Orders_Warehouse FOREIGN KEY (WarehouseID) REFERENCES dbo.Warehouses(WarehouseID),
    CONSTRAINT FK_Orders_Zone      FOREIGN KEY (ZoneID)      REFERENCES dbo.DeliveryZones(ZoneID)
);
GO


-- ============================================================
-- TABLE 4: Shipments
-- What it stores: Stage-by-stage tracking for each order
-- 3 key timestamps = 3 stages we will analyze
-- ============================================================
CREATE TABLE dbo.Shipments (
    ShipmentID              INT PRIMARY KEY,
    OrderID                 INT          NOT NULL,
    TrackingNumber          VARCHAR(20)  NOT NULL,
    WarehouseDispatchedAt   DATETIME     NOT NULL,   -- Stage 1 end: left origin warehouse
    TransitHubArrivedAt     DATETIME     NOT NULL,   -- Stage 2 start: reached mid-mile hub
    TransitHubDispatchedAt  DATETIME     NOT NULL,   -- Stage 2 end: left mid-mile hub
    DeliveredAt             DATETIME     NULL,        -- NULL = not yet delivered or RTO
    DeliveryStatus          VARCHAR(20)  NOT NULL,   -- Delivered / RTO / In Transit / Failed
    CourierPartner          VARCHAR(30)  NOT NULL,
    CONSTRAINT FK_Shipments_Order FOREIGN KEY (OrderID) REFERENCES dbo.Orders(OrderID)
);
GO


-- ============================================================
-- SEED DATA: Orders + Shipments (~500 rows)
-- Logic baked in:
--   Metro zones    → fast processing, on-time delivery
--   Tier2 zones    → slight delays
--   NE India zones → high processing time, mid-mile bottleneck,
--                    elevated RTO rate (15-20%)
-- ============================================================

-- Helper: We use a numbers approach to insert realistic data
-- Orders placed over Jan-May 2026, varied by zone type

-- ── Metro Orders (IDs 1-150) ─────────────────────────────
INSERT INTO dbo.Orders (OrderID, CustomerName, OrderPlacedAt, WarehouseID, ZoneID, ProductCategory, OrderValue_INR) VALUES
(1,  'Priya Sharma',      '2026-01-03 09:15:00', 1, 1, 'Electronics',  4500.00),
(2,  'Rahul Mehta',       '2026-01-03 10:30:00', 2, 2, 'Clothing',     1200.00),
(3,  'Ananya Singh',      '2026-01-04 11:00:00', 3, 3, 'Home Decor',   2300.00),
(4,  'Vikram Nair',       '2026-01-04 14:20:00', 5, 4, 'Books',         450.00),
(5,  'Deepa Iyer',        '2026-01-05 09:45:00', 7, 5, 'Electronics',  8900.00),
(6,  'Arjun Patel',       '2026-01-05 13:10:00', 1, 1, 'Sports',       3200.00),
(7,  'Kavitha Reddy',     '2026-01-06 10:00:00', 3, 3, 'Clothing',     1800.00),
(8,  'Suresh Kumar',      '2026-01-06 15:30:00', 2, 2, 'Electronics',  12000.00),
(9,  'Meena Krishnan',    '2026-01-07 09:00:00', 5, 4, 'Home Decor',   3400.00),
(10, 'Rajesh Verma',      '2026-01-07 11:45:00', 7, 5, 'Books',         780.00),
(11, 'Sunita Joshi',      '2026-01-08 10:20:00', 1, 1, 'Clothing',     2100.00),
(12, 'Anil Gupta',        '2026-01-08 14:00:00', 8, 6, 'Electronics',  6700.00),
(13, 'Pooja Mishra',      '2026-01-09 09:30:00', 3, 3, 'Sports',       4500.00),
(14, 'Kiran Rao',         '2026-01-09 12:15:00', 2, 2, 'Home Decor',   1900.00),
(15, 'Sanjay Pillai',     '2026-01-10 10:45:00', 5, 4, 'Clothing',     2600.00),
(16, 'Lakshmi Devi',      '2026-01-10 13:30:00', 7, 5, 'Electronics',  9800.00),
(17, 'Mohan Tiwari',      '2026-01-11 09:15:00', 1, 1, 'Books',         560.00),
(18, 'Rekha Bansal',      '2026-01-11 11:00:00', 3, 3, 'Sports',       3800.00),
(19, 'Vijay Saxena',      '2026-01-12 14:20:00', 2, 2, 'Clothing',     1500.00),
(20, 'Geetha Subramanian','2026-01-12 10:30:00', 5, 4, 'Electronics',  7200.00),
(21, 'Harish Chopra',     '2026-01-13 09:00:00', 8, 6, 'Home Decor',   2800.00),
(22, 'Usha Menon',        '2026-01-13 13:15:00', 7, 5, 'Books',         890.00),
(23, 'Prakash Yadav',     '2026-01-14 10:45:00', 1, 1, 'Electronics',  5600.00),
(24, 'Radha Nambiar',     '2026-01-14 12:00:00', 3, 3, 'Clothing',     2200.00),
(25, 'Santosh Ghosh',     '2026-01-15 09:30:00', 2, 2, 'Sports',       4100.00),
(26, 'Nalini Shetty',     '2026-01-15 14:45:00', 5, 4, 'Home Decor',   3300.00),
(27, 'Dinesh Kapoor',     '2026-01-16 10:00:00', 7, 5, 'Electronics',  11000.00),
(28, 'Kamala Subramaniam','2026-01-16 11:30:00', 1, 1, 'Books',         670.00),
(29, 'Ravi Shankar',      '2026-01-17 09:45:00', 3, 3, 'Clothing',     1700.00),
(30, 'Sheela Bhat',       '2026-01-17 13:00:00', 2, 2, 'Sports',       3600.00),
(31, 'Ashok Trivedi',     '2026-01-18 10:15:00', 8, 6, 'Electronics',  8400.00),
(32, 'Vani Parthasarathy','2026-01-18 12:45:00', 5, 4, 'Home Decor',   2100.00),
(33, 'Mahesh Kulkarni',   '2026-01-19 09:00:00', 7, 5, 'Books',         430.00),
(34, 'Saraswati Naidu',   '2026-01-19 11:15:00', 1, 1, 'Clothing',     2900.00),
(35, 'Gopal Krishna',     '2026-01-20 14:30:00', 3, 3, 'Electronics',  6300.00),
(36, 'Anita Fernandes',   '2026-01-20 10:00:00', 2, 2, 'Sports',       4800.00),
(37, 'Balaji Swaminathan','2026-01-21 09:30:00', 5, 4, 'Home Decor',   2500.00),
(38, 'Chitra Venkatesh',  '2026-01-21 13:45:00', 7, 5, 'Clothing',     1600.00),
(39, 'Devadas Pillai',    '2026-01-22 10:30:00', 1, 1, 'Electronics',  9200.00),
(40, 'Eswari Moorthy',    '2026-01-22 12:00:00', 3, 3, 'Books',         510.00),
(41, 'Ganesh Iyer',       '2026-01-23 09:15:00', 2, 2, 'Sports',       3900.00),
(42, 'Hema Krishnamurthy','2026-01-23 11:30:00', 5, 4, 'Home Decor',   2700.00),
(43, 'Indira Chatterjee', '2026-01-24 14:00:00', 7, 5, 'Electronics',  7800.00),
(44, 'Jagadish Bose',     '2026-01-24 10:15:00', 1, 1, 'Clothing',     2000.00),
(45, 'Kalpana Chawla',    '2026-01-25 09:45:00', 8, 6, 'Sports',       5200.00),
(46, 'Lalitha Devi',      '2026-01-25 13:00:00', 3, 3, 'Electronics',  10500.00),
(47, 'Murali Krishnan',   '2026-01-26 10:30:00', 2, 2, 'Books',         720.00),
(48, 'Nirmala Srinivas',  '2026-01-26 12:15:00', 5, 4, 'Home Decor',   3100.00),
(49, 'Om Prakash',        '2026-01-27 09:00:00', 7, 5, 'Clothing',     1900.00),
(50, 'Padmavathi Rao',    '2026-01-27 14:45:00', 1, 1, 'Electronics',  8100.00),
-- Continuing Metro (Feb 2026)
(51, 'Qasim Ali',         '2026-02-01 10:00:00', 3, 3, 'Sports',       4300.00),
(52, 'Radhalakshmi Nair', '2026-02-01 11:30:00', 2, 2, 'Home Decor',   2400.00),
(53, 'Sivakumar Pillai',  '2026-02-02 09:15:00', 5, 4, 'Clothing',     1700.00),
(54, 'Thenmozhi Arumugam','2026-02-02 13:45:00', 7, 5, 'Electronics',  6600.00),
(55, 'Uma Parvathi',      '2026-02-03 10:30:00', 1, 1, 'Books',         580.00),
(56, 'Vasantha Kumari',   '2026-02-03 12:00:00', 3, 3, 'Sports',       3700.00),
(57, 'Waman Deshpande',   '2026-02-04 09:45:00', 2, 2, 'Electronics',  11500.00),
(58, 'Xavier D''Souza',   '2026-02-04 14:15:00', 5, 4, 'Home Decor',   2900.00),
(59, 'Yamuna Devi',       '2026-02-05 10:00:00', 7, 5, 'Clothing',     2100.00),
(60, 'Zubeda Begum',      '2026-02-05 11:30:00', 1, 1, 'Electronics',  7400.00),
(61, 'Aakash Sharma',     '2026-02-06 09:30:00', 8, 6, 'Sports',       4600.00),
(62, 'Bhavani Sundaram',  '2026-02-06 13:00:00', 3, 3, 'Books',         640.00),
(63, 'Chiranjeevi Reddy', '2026-02-07 10:15:00', 2, 2, 'Home Decor',   3200.00),
(64, 'Dhanalakshmi Raj',  '2026-02-07 12:45:00', 5, 4, 'Electronics',  8700.00),
(65, 'Easwaran Nambiar',  '2026-02-08 09:00:00', 7, 5, 'Clothing',     1800.00),
(66, 'Fatima Siddiqui',   '2026-02-08 11:15:00', 1, 1, 'Sports',       5100.00),
(67, 'Gowri Shankar',     '2026-02-09 14:30:00', 3, 3, 'Electronics',  9300.00),
(68, 'Hemavathi Gowda',   '2026-02-09 10:45:00', 2, 2, 'Books',         490.00),
(69, 'Iraianbu Murugan',  '2026-02-10 09:15:00', 5, 4, 'Home Decor',   2600.00),
(70, 'Jayashree Menon',   '2026-02-10 13:30:00', 7, 5, 'Clothing',     2300.00),
(71, 'Karunanidhi Pillai','2026-02-11 10:00:00', 1, 1, 'Electronics',  10200.00),
(72, 'Leelavathi Naidu',  '2026-02-11 12:15:00', 3, 3, 'Sports',       3500.00),
(73, 'Manohar Lal',       '2026-02-12 09:45:00', 2, 2, 'Home Decor',   2800.00),
(74, 'Nallakannu Arasan', '2026-02-12 11:00:00', 5, 4, 'Electronics',  7100.00),
(75, 'Omana Thomas',      '2026-02-13 14:15:00', 7, 5, 'Books',         830.00),
-- Metro Mar-May sample
(76, 'Padma Lakshmi',     '2026-03-01 10:00:00', 1, 1, 'Electronics',  5500.00),
(77, 'Ramaswamy Iyer',    '2026-03-05 11:30:00', 3, 3, 'Clothing',     1900.00),
(78, 'Saroja Devi',       '2026-03-10 09:15:00', 2, 2, 'Sports',       4200.00),
(79, 'Tamilselvi Mutu',   '2026-03-15 13:45:00', 5, 4, 'Home Decor',   2700.00),
(80, 'Umamaheswari Raj',  '2026-03-20 10:30:00', 7, 5, 'Electronics',  8300.00),
(81, 'Veeraswamy Pillai', '2026-04-01 09:00:00', 1, 1, 'Books',         610.00),
(82, 'Wahida Rahman',     '2026-04-05 12:45:00', 3, 3, 'Sports',       3900.00),
(83, 'Xavieramma Joseph', '2026-04-10 10:15:00', 2, 2, 'Clothing',     2100.00),
(84, 'Yashoda Bai',       '2026-04-15 14:00:00', 5, 4, 'Electronics',  9600.00),
(85, 'Zaheer Ahmed',      '2026-04-20 09:30:00', 7, 5, 'Home Decor',   3100.00),
(86, 'Amudha Selvi',      '2026-05-01 11:00:00', 1, 1, 'Clothing',     2400.00),
(87, 'Balamurali Krishn', '2026-05-05 13:15:00', 3, 3, 'Electronics',  6800.00),
(88, 'Chandrakala Devi',  '2026-05-10 10:45:00', 2, 2, 'Sports',       4700.00),
(89, 'Deivanai Sundaram', '2026-05-15 09:00:00', 5, 4, 'Books',         750.00),
(90, 'Elangovan Murugan', '2026-05-20 12:30:00', 7, 5, 'Home Decor',   2900.00);
GO

-- ── Tier 2 Orders (IDs 101-200) ─────────────────────────
INSERT INTO dbo.Orders (OrderID, CustomerName, OrderPlacedAt, WarehouseID, ZoneID, ProductCategory, OrderValue_INR) VALUES
(101,'Arun Wadekar',      '2026-01-03 10:00:00', 8, 6,  'Electronics',  5200.00),
(102,'Beena Kulkarni',    '2026-01-04 11:30:00', 1, 7,  'Clothing',     1800.00),
(103,'Chandresh Shah',    '2026-01-05 09:15:00', 2, 8,  'Sports',       3600.00),
(104,'Devyani Mishra',    '2026-01-06 14:00:00', 2, 9,  'Home Decor',   2400.00),
(105,'Eknath Shinde',     '2026-01-07 10:30:00', 1, 10, 'Electronics',  7800.00),
(106,'Fulabai Patil',     '2026-01-08 12:15:00', 8, 6,  'Books',         920.00),
(107,'Ganpat Rane',       '2026-01-09 09:45:00', 1, 7,  'Clothing',     2200.00),
(108,'Harshal Thakur',    '2026-01-10 13:30:00', 2, 8,  'Sports',       4400.00),
(109,'Indumati Sawant',   '2026-01-11 10:00:00', 2, 9,  'Electronics',  8900.00),
(110,'Jagannath Rao',     '2026-01-12 11:45:00', 1, 10, 'Home Decor',   3100.00),
(111,'Kalpesh Joshi',     '2026-01-13 09:30:00', 8, 6,  'Books',         680.00),
(112,'Leelabai Desai',    '2026-01-14 14:15:00', 1, 7,  'Clothing',     1900.00),
(113,'Madhukar Pawar',    '2026-01-15 10:45:00', 2, 8,  'Sports',       5100.00),
(114,'Nalini Bhosale',    '2026-01-16 12:00:00', 2, 9,  'Electronics',  9200.00),
(115,'Omkar Bhave',       '2026-01-17 09:15:00', 1, 10, 'Home Decor',   2700.00),
(116,'Pushpalata Gaikwad','2026-01-18 13:45:00', 8, 6,  'Clothing',     2300.00),
(117,'Ramchandra Mane',   '2026-01-19 10:30:00', 1, 7,  'Electronics',  6400.00),
(118,'Sadhana Naik',      '2026-01-20 12:15:00', 2, 8,  'Books',         540.00),
(119,'Tanaji Shinde',     '2026-01-21 09:00:00', 2, 9,  'Sports',       4800.00),
(120,'Ujwala Jagtap',     '2026-01-22 11:30:00', 1, 10, 'Home Decor',   3400.00),
(121,'Vaibhav Chavan',    '2026-01-23 14:00:00', 8, 6,  'Electronics',  7600.00),
(122,'Warsha Kamble',     '2026-01-24 10:15:00', 1, 7,  'Clothing',     2000.00),
(123,'Yashwant Pol',      '2026-01-25 09:45:00', 2, 8,  'Sports',       3700.00),
(124,'Zeenat Sayyed',     '2026-01-26 13:00:00', 2, 9,  'Electronics',  10100.00),
(125,'Abhijit Deshpande', '2026-01-27 11:15:00', 1, 10, 'Books',         810.00),
(126,'Bhagyashri More',   '2026-02-01 10:30:00', 8, 6,  'Home Decor',   2600.00),
(127,'Chaitanya Gokhale', '2026-02-05 12:45:00', 1, 7,  'Clothing',     1700.00),
(128,'Damayanti Thite',   '2026-02-10 09:00:00', 2, 8,  'Electronics',  8300.00),
(129,'Ekatma Prabhu',     '2026-02-15 11:15:00', 2, 9,  'Sports',       4100.00),
(130,'Gangadhar Sutar',   '2026-02-20 14:30:00', 1, 10, 'Home Decor',   2900.00),
(131,'Hirabai Lokhande',  '2026-03-01 10:00:00', 8, 6,  'Electronics',  5800.00),
(132,'Ishwarlal Patil',   '2026-03-05 12:15:00', 1, 7,  'Clothing',     2100.00),
(133,'Jijabai Bhosale',   '2026-03-10 09:30:00', 2, 8,  'Books',         760.00),
(134,'Kashinath Bhor',    '2026-03-15 13:45:00', 2, 9,  'Sports',       4600.00),
(135,'Laxmibai Shinde',   '2026-03-20 10:15:00', 1, 10, 'Electronics',  9700.00),
(136,'Mangesh Kulkarni',  '2026-04-01 11:30:00', 8, 6,  'Home Decor',   3200.00),
(137,'Nandadevi Gavhane', '2026-04-05 09:45:00', 1, 7,  'Clothing',     1800.00),
(138,'Onkar Suryavanshi', '2026-04-10 14:00:00', 2, 8,  'Sports',       5300.00),
(139,'Prabodhan Bagal',   '2026-04-15 10:30:00', 2, 9,  'Electronics',  8600.00),
(140,'Qutub Munshi',      '2026-04-20 12:00:00', 1, 10, 'Books',         690.00),
(141,'Ratnamala Pawar',   '2026-05-01 09:15:00', 8, 6,  'Home Decor',   2800.00),
(142,'Sudhakar Desai',    '2026-05-05 13:30:00', 1, 7,  'Clothing',     2200.00),
(143,'Taramati Salve',    '2026-05-10 10:45:00', 2, 8,  'Electronics',  7200.00),
(144,'Ulhas Nimbalkar',   '2026-05-15 12:15:00', 2, 9,  'Sports',       4200.00),
(145,'Vasudha Pingle',    '2026-05-20 09:00:00', 1, 10, 'Home Decor',   3500.00);
GO

-- ── NE India Orders (IDs 201-350) — intentional delays ──
INSERT INTO dbo.Orders (OrderID, CustomerName, OrderPlacedAt, WarehouseID, ZoneID, ProductCategory, OrderValue_INR) VALUES
(201,'Bhupen Hazarika',   '2026-01-03 09:00:00', 4,  11, 'Electronics',  6200.00),
(202,'Arup Sarma',        '2026-01-03 10:30:00', 6,  12, 'Clothing',     1900.00),
(203,'Dimple Baruah',     '2026-01-04 09:15:00', 4,  13, 'Sports',       3800.00),
(204,'Gitima Borah',      '2026-01-04 11:00:00', 6,  14, 'Home Decor',   2600.00),
(205,'Hemen Deka',        '2026-01-05 09:45:00', 9,  15, 'Electronics',  9100.00),
(206,'Jyoti Prasad',      '2026-01-05 13:00:00', 4,  16, 'Books',         870.00),
(207,'Karabi Das',        '2026-01-06 10:15:00', 6,  17, 'Clothing',     2300.00),
(208,'Lakhi Sharma',      '2026-01-06 12:30:00', 10, 18, 'Electronics',  7500.00),
(209,'Manab Deka',        '2026-01-07 09:00:00', 4,  19, 'Sports',       4400.00),
(210,'Nayan Moni',        '2026-01-07 14:15:00', 6,  20, 'Home Decor',   3100.00),
(211,'Padma Bora',        '2026-01-08 10:30:00', 9,  11, 'Electronics',  8800.00),
(212,'Ranju Das',         '2026-01-08 12:00:00', 4,  12, 'Clothing',     2100.00),
(213,'Sailen Sarmah',     '2026-01-09 09:30:00', 6,  13, 'Sports',       5200.00),
(214,'Tarali Sarma',      '2026-01-09 13:45:00', 10, 14, 'Books',         740.00),
(215,'Utpal Dutta',       '2026-01-10 10:00:00', 4,  15, 'Home Decor',   2800.00),
(216,'Vijay Barua',       '2026-01-10 11:30:00', 6,  16, 'Electronics',  10300.00),
(217,'Wahab Ali',         '2026-01-11 09:15:00', 9,  17, 'Clothing',     1700.00),
(218,'Ximi Marak',        '2026-01-11 14:00:00', 4,  18, 'Sports',       4900.00),
(219,'Yumnam Singh',      '2026-01-12 10:45:00', 6,  19, 'Electronics',  7200.00),
(220,'Zubeen Garg',       '2026-01-12 12:15:00', 10, 20, 'Home Decor',   3400.00),
(221,'Abhijit Bhattachar','2026-01-13 09:00:00', 4,  11, 'Books',         920.00),
(222,'Bina Choudhury',    '2026-01-13 10:30:00', 6,  12, 'Clothing',     2400.00),
(223,'Champak Baruah',    '2026-01-14 09:45:00', 9,  13, 'Electronics',  6800.00),
(224,'Dharitri Deka',     '2026-01-14 13:00:00', 4,  14, 'Sports',       5100.00),
(225,'Elora Hazarika',    '2026-01-15 10:15:00', 6,  15, 'Home Decor',   2900.00),
(226,'Fatik Choudhury',   '2026-01-15 12:30:00', 10, 16, 'Electronics',  9400.00),
(227,'Gyan Deka',         '2026-01-16 09:30:00', 4,  17, 'Books',         650.00),
(228,'Hiranmoy Baruah',   '2026-01-16 14:45:00', 6,  18, 'Clothing',     2000.00),
(229,'Ila Bora',          '2026-01-17 10:00:00', 9,  19, 'Sports',       4700.00),
(230,'Jadav Payeng',      '2026-01-17 11:30:00', 4,  20, 'Electronics',  8100.00),
(231,'Kanak Sarmah',      '2026-01-18 09:15:00', 6,  11, 'Home Decor',   3200.00),
(232,'Labanya Das',       '2026-01-18 13:00:00', 10, 12, 'Clothing',     1800.00),
(233,'Madhab Gogoi',      '2026-01-19 10:30:00', 4,  13, 'Electronics',  7600.00),
(234,'Nripen Baruah',     '2026-01-19 12:15:00', 6,  14, 'Sports',       4300.00),
(235,'Oindri Sarma',      '2026-01-20 09:00:00', 9,  15, 'Books',         780.00),
(236,'Prabin Kalita',     '2026-01-20 14:30:00', 4,  16, 'Home Decor',   2700.00),
(237,'Quazi Noor',        '2026-01-21 10:45:00', 6,  17, 'Electronics',  10800.00),
(238,'Rekibuddin Ahmed',  '2026-01-21 12:00:00', 10, 18, 'Clothing',     2200.00),
(239,'Sanjib Barua',      '2026-01-22 09:30:00', 4,  19, 'Sports',       5500.00),
(240,'Thangamani Devi',   '2026-01-22 11:15:00', 6,  20, 'Electronics',  8700.00),
(241,'Upendra Nath',      '2026-01-23 14:00:00', 9,  11, 'Home Decor',   3000.00),
(242,'Vibha Sarma',       '2026-01-23 10:30:00', 4,  12, 'Books',         830.00),
(243,'Wangchuk Bhutia',   '2026-01-24 09:15:00', 6,  13, 'Clothing',     1900.00),
(244,'Xiphi Barman',      '2026-01-24 13:45:00', 10, 14, 'Electronics',  7100.00),
(245,'Yogesh Saikia',     '2026-01-25 10:00:00', 4,  15, 'Sports',       4600.00),
(246,'Zafar Hussain',     '2026-01-25 12:30:00', 6,  16, 'Home Decor',   2500.00),
(247,'Amrita Gogoi',      '2026-01-26 09:45:00', 9,  17, 'Electronics',  9600.00),
(248,'Biju Phukan',       '2026-01-26 11:00:00', 4,  18, 'Clothing',     2100.00),
(249,'Chandan Kakati',    '2026-01-27 14:15:00', 6,  19, 'Sports',       4800.00),
(250,'Dulumoni Bora',     '2026-01-27 10:30:00', 10, 20, 'Electronics',  8400.00),
-- Feb NE India
(251,'Emon Gogoi',        '2026-02-01 09:00:00', 4,  11, 'Home Decor',   2900.00),
(252,'Firoz Ahmed',       '2026-02-03 10:30:00', 6,  12, 'Books',         710.00),
(253,'Gargi Sharma',      '2026-02-05 09:15:00', 9,  13, 'Clothing',     2300.00),
(254,'Hirak Jyoti',       '2026-02-07 13:00:00', 4,  14, 'Electronics',  7800.00),
(255,'Indira Bora',       '2026-02-09 10:45:00', 6,  15, 'Sports',       4100.00),
(256,'Jayanta Bhuyan',    '2026-02-11 12:00:00', 10, 16, 'Home Decor',   3300.00),
(257,'Kiran Saikia',      '2026-02-13 09:30:00', 4,  17, 'Electronics',  9900.00),
(258,'Lipika Baruah',     '2026-02-15 14:45:00', 6,  18, 'Clothing',     1800.00),
(259,'Mrigen Deka',       '2026-02-17 10:15:00', 9,  19, 'Sports',       5300.00),
(260,'Nayan Hazarika',    '2026-02-19 11:30:00', 4,  20, 'Electronics',  8200.00),
-- Mar-May NE India
(261,'Opu Sarma',         '2026-03-01 09:00:00', 6,  11, 'Books',         860.00),
(262,'Paban Das',         '2026-03-05 10:30:00', 10, 12, 'Home Decor',   2600.00),
(263,'Queen Hoda',        '2026-03-10 09:45:00', 4,  13, 'Clothing',     2000.00),
(264,'Raktim Bora',       '2026-03-15 13:15:00', 6,  14, 'Electronics',  10200.00),
(265,'Santipriya Deka',   '2026-03-20 10:00:00', 9,  15, 'Sports',       4500.00),
(266,'Tapan Kalita',      '2026-04-01 12:30:00', 4,  16, 'Home Decor',   3100.00),
(267,'Urmila Phukan',     '2026-04-05 09:15:00', 6,  17, 'Electronics',  7400.00),
(268,'Vivek Sarma',       '2026-04-10 11:00:00', 10, 18, 'Clothing',     2200.00),
(269,'Wasim Akram',       '2026-04-15 14:30:00', 4,  19, 'Sports',       5700.00),
(270,'Xenith Das',        '2026-04-20 10:45:00', 6,  20, 'Electronics',  8900.00),
(271,'Yasmin Begum',      '2026-05-01 09:00:00', 9,  11, 'Home Decor',   3400.00),
(272,'Zubeen Hazarika',   '2026-05-05 12:15:00', 4,  12, 'Books',         740.00),
(273,'Ankur Gogoi',       '2026-05-10 10:30:00', 6,  13, 'Clothing',     1900.00),
(274,'Banani Roy',        '2026-05-15 09:45:00', 10, 14, 'Electronics',  7600.00),
(275,'Chintu Saikia',     '2026-05-20 13:00:00', 4,  15, 'Sports',       4300.00);
GO


-- ============================================================
-- SHIPMENTS SEED DATA
-- Key design:
--   Metro    → processing 4-5 hrs, mid-mile 24-36 hrs, last mile 24-48 hrs
--   Tier 2   → processing 5-7 hrs, mid-mile 36-48 hrs, last mile 48-72 hrs
--   NE India → processing 9-18 hrs (BOTTLENECK), mid-mile 72-120 hrs (BOTTLENECK)
--              last mile 48-96 hrs, RTO rate ~18%
-- ============================================================

-- Metro Shipments (fast, mostly delivered)
INSERT INTO dbo.Shipments (ShipmentID, OrderID, TrackingNumber, WarehouseDispatchedAt, TransitHubArrivedAt, TransitHubDispatchedAt, DeliveredAt, DeliveryStatus, CourierPartner) VALUES
(1001,1,  'DL2601030001', '2026-01-03 13:45:00', '2026-01-03 22:00:00', '2026-01-04 06:00:00', '2026-01-04 14:30:00', 'Delivered',   'Delhivery'),
(1002,2,  'DL2601030002', '2026-01-03 16:00:00', '2026-01-04 00:30:00', '2026-01-04 08:00:00', '2026-01-04 17:00:00', 'Delivered',   'Delhivery'),
(1003,3,  'DL2601040003', '2026-01-04 15:30:00', '2026-01-04 23:00:00', '2026-01-05 07:00:00', '2026-01-05 15:45:00', 'Delivered',   'BlueDart'),
(1004,4,  'BD2601040004', '2026-01-04 19:00:00', '2026-01-05 03:30:00', '2026-01-05 09:00:00', '2026-01-05 16:30:00', 'Delivered',   'BlueDart'),
(1005,5,  'DL2601050005', '2026-01-05 14:15:00', '2026-01-05 22:30:00', '2026-01-06 06:30:00', '2026-01-06 14:00:00', 'Delivered',   'Delhivery'),
(1006,6,  'DL2601050006', '2026-01-05 17:40:00', '2026-01-06 02:00:00', '2026-01-06 08:30:00', '2026-01-06 17:15:00', 'Delivered',   'Delhivery'),
(1007,7,  'BD2601060007', '2026-01-06 14:30:00', '2026-01-06 23:00:00', '2026-01-07 07:00:00', '2026-01-07 16:00:00', 'Delivered',   'BlueDart'),
(1008,8,  'DL2601060008', '2026-01-06 20:00:00', '2026-01-07 04:30:00', '2026-01-07 10:00:00', '2026-01-07 18:30:00', 'Delivered',   'Delhivery'),
(1009,9,  'DL2601070009', '2026-01-07 13:30:00', '2026-01-07 22:00:00', '2026-01-08 06:00:00', '2026-01-08 15:00:00', 'Delivered',   'Delhivery'),
(1010,10, 'BD2601070010', '2026-01-07 16:15:00', '2026-01-08 00:30:00', '2026-01-08 08:30:00', '2026-01-08 17:45:00', 'Delivered',   'BlueDart'),
(1011,11, 'DL2601080011', '2026-01-08 14:50:00', '2026-01-08 23:00:00', '2026-01-09 07:00:00', '2026-01-09 14:30:00', 'Delivered',   'Delhivery'),
(1012,12, 'DL2601080012', '2026-01-08 18:30:00', '2026-01-09 03:00:00', '2026-01-09 09:00:00', '2026-01-09 18:00:00', 'Delivered',   'Delhivery'),
(1013,13, 'BD2601090013', '2026-01-09 14:00:00', '2026-01-09 22:30:00', '2026-01-10 06:30:00', '2026-01-10 15:15:00', 'Delivered',   'BlueDart'),
(1014,14, 'DL2601090014', '2026-01-09 16:45:00', '2026-01-10 01:00:00', '2026-01-10 09:00:00', '2026-01-10 17:30:00', 'Delivered',   'Delhivery'),
(1015,15, 'DL2601100015', '2026-01-10 15:15:00', '2026-01-10 23:30:00', '2026-01-11 07:30:00', '2026-01-11 16:00:00', 'Delivered',   'Delhivery'),
(1016,16, 'BD2601100016', '2026-01-10 17:00:00', '2026-01-11 01:30:00', '2026-01-11 09:30:00', '2026-01-11 18:15:00', 'Delivered',   'BlueDart'),
(1017,17, 'DL2601110017', '2026-01-11 13:45:00', '2026-01-11 22:00:00', '2026-01-12 06:00:00', '2026-01-12 14:30:00', 'Delivered',   'Delhivery'),
(1018,18, 'DL2601110018', '2026-01-11 15:30:00', '2026-01-11 23:45:00', '2026-01-12 08:00:00', '2026-01-12 16:45:00', 'Delivered',   'Delhivery'),
(1019,19, 'BD2601120019', '2026-01-12 18:50:00', '2026-01-13 03:00:00', '2026-01-13 09:00:00', '2026-01-13 17:00:00', 'Delivered',   'BlueDart'),
(1020,20, 'DL2601120020', '2026-01-12 15:00:00', '2026-01-12 23:30:00', '2026-01-13 07:30:00', '2026-01-13 15:30:00', 'Delivered',   'Delhivery'),
(1021,21, 'DL2601130021', '2026-01-13 13:30:00', '2026-01-13 22:00:00', '2026-01-14 06:00:00', '2026-01-14 15:00:00', 'Delivered',   'Delhivery'),
(1022,22, 'BD2601130022', '2026-01-13 17:45:00', '2026-01-14 02:00:00', '2026-01-14 08:30:00', '2026-01-14 17:30:00', 'Delivered',   'BlueDart'),
(1023,23, 'DL2601140023', '2026-01-14 15:15:00', '2026-01-14 23:30:00', '2026-01-15 07:30:00', '2026-01-15 15:00:00', 'Delivered',   'Delhivery'),
(1024,24, 'DL2601140024', '2026-01-14 16:30:00', '2026-01-15 01:00:00', '2026-01-15 09:00:00', '2026-01-15 17:45:00', 'Delivered',   'Delhivery'),
(1025,25, 'BD2601150025', '2026-01-15 14:00:00', '2026-01-15 22:30:00', '2026-01-16 06:30:00', '2026-01-16 14:30:00', 'Delivered',   'BlueDart'),
-- Tier 2 Shipments (moderate delays)
(2001,101,'DL2601030101', '2026-01-03 15:30:00', '2026-01-04 07:00:00', '2026-01-04 19:00:00', '2026-01-05 18:00:00', 'Delivered',   'Delhivery'),
(2002,102,'DL2601040102', '2026-01-04 17:00:00', '2026-01-05 09:30:00', '2026-01-05 21:30:00', '2026-01-06 20:00:00', 'Delivered',   'Delhivery'),
(2003,103,'BD2601050103', '2026-01-05 14:45:00', '2026-01-06 08:00:00', '2026-01-06 20:00:00', '2026-01-07 19:30:00', 'Delivered',   'BlueDart'),
(2004,104,'DL2601060104', '2026-01-06 19:30:00', '2026-01-07 11:00:00', '2026-01-07 23:00:00', '2026-01-08 22:00:00', 'Delivered',   'Delhivery'),
(2005,105,'DL2601070105', '2026-01-07 16:00:00', '2026-01-08 08:30:00', '2026-01-08 20:30:00', '2026-01-09 20:00:00', 'Delivered',   'Delhivery'),
(2006,106,'BD2601080106', '2026-01-08 19:45:00', '2026-01-09 12:00:00', '2026-01-10 00:00:00', '2026-01-10 23:00:00', 'Delivered',   'BlueDart'),
(2007,107,'DL2601090107', '2026-01-09 15:15:00', '2026-01-10 07:30:00', '2026-01-10 19:30:00', '2026-01-11 18:30:00', 'Delivered',   'Delhivery'),
(2008,108,'DL2601100108', '2026-01-10 19:00:00', '2026-01-11 11:30:00', '2026-01-11 23:30:00', '2026-01-12 22:30:00', 'Delivered',   'Delhivery'),
(2009,109,'BD2601110109', '2026-01-11 15:30:00', '2026-01-12 08:00:00', '2026-01-12 20:00:00', '2026-01-13 19:30:00', 'Delivered',   'BlueDart'),
(2010,110,'DL2601120110', '2026-01-12 17:15:00', '2026-01-13 09:30:00', '2026-01-13 21:30:00', '2026-01-14 21:00:00', 'Delivered',   'Delhivery'),
-- NE India Shipments — BOTTLENECK DATA (high processing, high mid-mile delay, RTO cases)
(3001,201,'DL2601030201', '2026-01-03 20:30:00', '2026-01-05 14:00:00', '2026-01-07 08:00:00', '2026-01-08 18:30:00', 'Delivered',   'Delhivery'),
(3002,202,'DL2601030202', '2026-01-03 22:00:00', '2026-01-05 18:00:00', '2026-01-07 14:00:00', '2026-01-09 10:00:00', 'Delivered',   'Delhivery'),
(3003,203,'BD2601040203', '2026-01-04 21:45:00', '2026-01-06 20:00:00', '2026-01-09 08:00:00', NULL,                  'RTO',         'BlueDart'),
(3004,204,'DL2601040204', '2026-01-04 23:30:00', '2026-01-07 00:00:00', '2026-01-09 12:00:00', '2026-01-11 08:00:00', 'Delivered',   'Delhivery'),
(3005,205,'DL2601050205', '2026-01-05 22:00:00', '2026-01-07 22:00:00', '2026-01-10 10:00:00', NULL,                  'RTO',         'Delhivery'),
(3006,206,'BD2601050206', '2026-01-05 23:15:00', '2026-01-07 20:00:00', '2026-01-10 06:00:00', '2026-01-12 14:00:00', 'Delivered',   'BlueDart'),
(3007,207,'DL2601060207', '2026-01-06 22:30:00', '2026-01-08 22:00:00', '2026-01-11 10:00:00', '2026-01-13 08:00:00', 'Delivered',   'Delhivery'),
(3008,208,'DL2601060208', '2026-01-07 00:00:00', '2026-01-09 02:00:00', '2026-01-11 18:00:00', NULL,                  'RTO',         'Delhivery'),
(3009,209,'BD2601070209', '2026-01-07 20:45:00', '2026-01-09 20:00:00', '2026-01-12 08:00:00', '2026-01-14 10:00:00', 'Delivered',   'BlueDart'),
(3010,210,'DL2601070210', '2026-01-08 02:00:00', '2026-01-10 04:00:00', '2026-01-12 16:00:00', '2026-01-14 18:00:00', 'Delivered',   'Delhivery'),
(3011,211,'DL2601080211', '2026-01-08 22:30:00', '2026-01-10 22:00:00', '2026-01-13 10:00:00', NULL,                  'RTO',         'Delhivery'),
(3012,212,'BD2601080212', '2026-01-08 20:00:00', '2026-01-10 20:00:00', '2026-01-13 08:00:00', '2026-01-15 12:00:00', 'Delivered',   'BlueDart'),
(3013,213,'DL2601090213', '2026-01-09 21:30:00', '2026-01-11 22:00:00', '2026-01-14 10:00:00', '2026-01-16 14:00:00', 'Delivered',   'Delhivery'),
(3014,214,'DL2601090214', '2026-01-09 23:00:00', '2026-01-12 00:00:00', '2026-01-14 16:00:00', NULL,                  'RTO',         'Delhivery'),
(3015,215,'BD2601100215', '2026-01-10 21:30:00', '2026-01-12 22:00:00', '2026-01-15 10:00:00', '2026-01-17 08:00:00', 'Delivered',   'BlueDart'),
(3016,216,'DL2601100216', '2026-01-10 23:00:00', '2026-01-13 00:00:00', '2026-01-15 16:00:00', '2026-01-17 20:00:00', 'Delivered',   'Delhivery'),
(3017,217,'DL2601110217', '2026-01-11 22:15:00', '2026-01-13 22:00:00', '2026-01-16 10:00:00', NULL,                  'RTO',         'Delhivery'),
(3018,218,'BD2601110218', '2026-01-12 02:30:00', '2026-01-14 04:00:00', '2026-01-16 20:00:00', '2026-01-19 10:00:00', 'Delivered',   'BlueDart'),
(3019,219,'DL2601120219', '2026-01-12 23:15:00', '2026-01-15 00:00:00', '2026-01-17 12:00:00', '2026-01-19 16:00:00', 'Delivered',   'Delhivery'),
(3020,220,'DL2601120220', '2026-01-13 01:00:00', '2026-01-15 02:00:00', '2026-01-17 18:00:00', NULL,                  'RTO',         'Delhivery'),
(3021,221,'BD2601130221', '2026-01-13 21:30:00', '2026-01-15 22:00:00', '2026-01-18 10:00:00', '2026-01-20 14:00:00', 'Delivered',   'BlueDart'),
(3022,222,'DL2601130222', '2026-01-13 23:00:00', '2026-01-16 00:00:00', '2026-01-18 16:00:00', '2026-01-20 18:00:00', 'Delivered',   'Delhivery'),
(3023,223,'DL2601140223', '2026-01-14 22:15:00', '2026-01-16 22:00:00', '2026-01-19 10:00:00', NULL,                  'RTO',         'Delhivery'),
(3024,224,'BD2601140224', '2026-01-15 01:30:00', '2026-01-17 02:00:00', '2026-01-19 18:00:00', '2026-01-21 20:00:00', 'Delivered',   'BlueDart'),
(3025,225,'DL2601150225', '2026-01-15 23:45:00', '2026-01-18 00:00:00', '2026-01-20 12:00:00', '2026-01-22 16:00:00', 'Delivered',   'Delhivery'),
(3026,226,'DL2601150226', '2026-01-16 01:00:00', '2026-01-18 02:00:00', '2026-01-20 18:00:00', '2026-01-22 22:00:00', 'Delivered',   'Delhivery'),
(3027,227,'BD2601160227', '2026-01-16 22:30:00', '2026-01-18 22:00:00', '2026-01-21 10:00:00', NULL,                  'RTO',         'BlueDart'),
(3028,228,'DL2601160228', '2026-01-17 01:15:00', '2026-01-19 02:00:00', '2026-01-21 18:00:00', '2026-01-23 22:00:00', 'Delivered',   'Delhivery'),
(3029,229,'DL2601170229', '2026-01-17 22:45:00', '2026-01-19 22:00:00', '2026-01-22 10:00:00', '2026-01-24 14:00:00', 'Delivered',   'Delhivery'),
(3030,230,'BD2601170230', '2026-01-18 00:00:00', '2026-01-20 02:00:00', '2026-01-22 18:00:00', '2026-01-24 22:00:00', 'Delivered',   'BlueDart'),
(3031,231,'DL2601180231', '2026-01-18 21:45:00', '2026-01-20 22:00:00', '2026-01-23 10:00:00', NULL,                  'RTO',         'Delhivery'),
(3032,232,'DL2601180232', '2026-01-19 00:30:00', '2026-01-21 02:00:00', '2026-01-23 18:00:00', '2026-01-25 22:00:00', 'Delivered',   'Delhivery'),
(3033,233,'BD2601190233', '2026-01-19 22:00:00', '2026-01-21 22:00:00', '2026-01-24 10:00:00', '2026-01-26 14:00:00', 'Delivered',   'BlueDart'),
(3034,234,'DL2601190234', '2026-01-19 23:45:00', '2026-01-22 00:00:00', '2026-01-24 16:00:00', '2026-01-26 20:00:00', 'Delivered',   'Delhivery'),
(3035,235,'DL2601200235', '2026-01-20 21:30:00', '2026-01-22 22:00:00', '2026-01-25 10:00:00', NULL,                  'RTO',         'Delhivery'),
(3036,236,'BD2601200236', '2026-01-21 02:00:00', '2026-01-23 04:00:00', '2026-01-25 20:00:00', '2026-01-28 00:00:00', 'Delivered',   'BlueDart'),
(3037,237,'DL2601210237', '2026-01-21 23:15:00', '2026-01-24 00:00:00', '2026-01-26 12:00:00', '2026-01-28 16:00:00', 'Delivered',   'Delhivery'),
(3038,238,'DL2601210238', '2026-01-22 01:30:00', '2026-01-24 02:00:00', '2026-01-26 18:00:00', '2026-01-29 00:00:00', 'Delivered',   'Delhivery'),
(3039,239,'BD2601220239', '2026-01-22 22:00:00', '2026-01-24 22:00:00', '2026-01-27 10:00:00', NULL,                  'RTO',         'BlueDart'),
(3040,240,'DL2601220240', '2026-01-23 00:45:00', '2026-01-25 02:00:00', '2026-01-27 18:00:00', '2026-01-30 00:00:00', 'Delivered',   'Delhivery'),
(3041,241,'DL2601230241', '2026-01-23 22:30:00', '2026-01-25 22:00:00', '2026-01-28 10:00:00', '2026-01-30 14:00:00', 'Delivered',   'Delhivery'),
(3042,242,'BD2601230242', '2026-01-24 01:15:00', '2026-01-26 02:00:00', '2026-01-28 18:00:00', '2026-01-31 00:00:00', 'Delivered',   'BlueDart'),
(3043,243,'DL2601240243', '2026-01-24 22:45:00', '2026-01-26 22:00:00', '2026-01-29 10:00:00', NULL,                  'RTO',         'Delhivery'),
(3044,244,'DL2601240244', '2026-01-25 01:00:00', '2026-01-27 02:00:00', '2026-01-29 18:00:00', '2026-02-01 00:00:00', 'Delivered',   'Delhivery'),
(3045,245,'BD2601250245', '2026-01-25 22:30:00', '2026-01-27 22:00:00', '2026-01-30 10:00:00', '2026-02-01 14:00:00', 'Delivered',   'BlueDart'),
(3046,246,'DL2601250246', '2026-01-26 01:15:00', '2026-01-28 02:00:00', '2026-01-30 18:00:00', '2026-02-02 00:00:00', 'Delivered',   'Delhivery'),
(3047,247,'DL2601260247', '2026-01-26 22:45:00', '2026-01-28 22:00:00', '2026-01-31 10:00:00', NULL,                  'RTO',         'Delhivery'),
(3048,248,'BD2601260248', '2026-01-27 01:30:00', '2026-01-29 02:00:00', '2026-01-31 18:00:00', '2026-02-03 00:00:00', 'Delivered',   'BlueDart'),
(3049,249,'DL2601270249', '2026-01-27 22:45:00', '2026-01-29 22:00:00', '2026-02-01 10:00:00', '2026-02-03 14:00:00', 'Delivered',   'Delhivery'),
(3050,250,'DL2601270250', '2026-01-28 01:00:00', '2026-01-30 02:00:00', '2026-02-01 18:00:00', '2026-02-04 00:00:00', 'Delivered',   'Delhivery');
GO

-- Verify row counts
SELECT 'DeliveryZones' AS TableName, COUNT(*) AS TotalRows FROM dbo.DeliveryZones
UNION ALL
SELECT 'Warehouses',  COUNT(*) FROM dbo.Warehouses
UNION ALL
SELECT 'Orders',      COUNT(*) FROM dbo.Orders
UNION ALL
SELECT 'Shipments',   COUNT(*) FROM dbo.Shipments;
GO

-- Quick sanity check: NE India vs Metro avg lead time preview
SELECT
    dz.Region,
    COUNT(s.ShipmentID) AS TotalShipments,
    SUM(CASE WHEN s.DeliveryStatus = 'RTO' THEN 1 ELSE 0 END) AS RTOCount,
    CAST(SUM(CASE WHEN s.DeliveryStatus = 'RTO' THEN 1.0 ELSE 0 END) / COUNT(*) * 100 AS DECIMAL(5,1)) AS RTO_Pct
FROM dbo.Shipments s
JOIN dbo.Orders o    ON s.OrderID = o.OrderID
JOIN dbo.DeliveryZones dz ON o.ZoneID = dz.ZoneID
GROUP BY dz.Region
ORDER BY RTO_Pct DESC;
GO

-- ============================================================
-- PHASE 1 COMPLETE ✅
-- Next: Phase 2 — Lead Time window function queries
-- ============================================================


-- Phase 2 — Lead Time window function queries


SELECT
    s.ShipmentID,
    o.OrderID,
    dz.Region,
    dz.ZoneName,
    w.WarehouseName,
    s.DeliveryStatus,

    -- Stage 1: Warehouse Processing (Order placed → Dispatched from warehouse)
    DATEDIFF(HOUR, o.OrderPlacedAt, s.WarehouseDispatchedAt) 
        AS WH_Processing_Hrs,

    -- Stage 2: Mid-Mile (Warehouse dispatched → Transit hub dispatched)
    DATEDIFF(HOUR, s.WarehouseDispatchedAt, s.TransitHubDispatchedAt) 
        AS MidMile_Hrs,

    -- Stage 3: Last Mile (Transit hub dispatched → Delivered)
    -- NULL if RTO, so we handle that
    DATEDIFF(HOUR, s.TransitHubDispatchedAt, s.DeliveredAt) 
        AS LastMile_Hrs,

    -- Total Lead Time (only for delivered shipments)
    DATEDIFF(HOUR, o.OrderPlacedAt, s.DeliveredAt) 
        AS Total_LeadTime_Hrs

FROM dbo.Shipments s
JOIN dbo.Orders o       ON s.OrderID = o.OrderID
JOIN dbo.DeliveryZones dz ON o.ZoneID = dz.ZoneID
JOIN dbo.Warehouses w   ON o.WarehouseID = w.WarehouseID
ORDER BY dz.Region, s.ShipmentID;


--------------------------------------------------------------------

SELECT
    dz.Region,
    COUNT(s.ShipmentID)                                         AS TotalShipments,
    ROUND(AVG(CAST(DATEDIFF(HOUR, o.OrderPlacedAt, 
        s.WarehouseDispatchedAt) AS FLOAT)), 1)                 AS Avg_WH_Processing_Hrs,
    ROUND(AVG(CAST(DATEDIFF(HOUR, s.WarehouseDispatchedAt, 
        s.TransitHubDispatchedAt) AS FLOAT)), 1)               AS Avg_MidMile_Hrs,
    ROUND(AVG(CAST(DATEDIFF(HOUR, s.TransitHubDispatchedAt, 
        s.DeliveredAt) AS FLOAT)), 1)                          AS Avg_LastMile_Hrs,
    ROUND(AVG(CAST(DATEDIFF(HOUR, o.OrderPlacedAt, 
        s.DeliveredAt) AS FLOAT)), 1)                          AS Avg_Total_LeadTime_Hrs,
    SUM(CASE WHEN s.DeliveryStatus = 'RTO' THEN 1 ELSE 0 END)  AS RTO_Count,
    ROUND(CAST(SUM(CASE WHEN s.DeliveryStatus = 'RTO' 
        THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*) * 100, 1)     AS RTO_Pct
FROM dbo.Shipments s
JOIN dbo.Orders o        ON s.OrderID = o.OrderID
JOIN dbo.DeliveryZones dz ON o.ZoneID = dz.ZoneID
GROUP BY dz.Region
ORDER BY Avg_Total_LeadTime_Hrs DESC;

------------------------------------------------------------------------------------

SELECT
    s.ShipmentID,
    dz.Region,
    dz.ZoneName,
    w.WarehouseName,
    s.DeliveryStatus,

    DATEDIFF(HOUR, o.OrderPlacedAt, s.WarehouseDispatchedAt) 
        AS WH_Processing_Hrs,
    DATEDIFF(HOUR, s.WarehouseDispatchedAt, s.TransitHubDispatchedAt) 
        AS MidMile_Hrs,
    DATEDIFF(HOUR, s.TransitHubDispatchedAt, s.DeliveredAt) 
        AS LastMile_Hrs,
    DATEDIFF(HOUR, o.OrderPlacedAt, s.DeliveredAt) 
        AS Total_LeadTime_Hrs,

    -- Window function: rank each shipment within its region by total lead time
    RANK() OVER (
        PARTITION BY dz.Region 
        ORDER BY DATEDIFF(HOUR, o.OrderPlacedAt, s.DeliveredAt) DESC
    ) AS Rank_Within_Region,

    -- Window function: how does this shipment compare to region average
    DATEDIFF(HOUR, o.OrderPlacedAt, s.DeliveredAt) -
        AVG(DATEDIFF(HOUR, o.OrderPlacedAt, s.DeliveredAt)) 
        OVER (PARTITION BY dz.Region) 
        AS Hrs_Above_Region_Avg

FROM dbo.Shipments s
JOIN dbo.Orders o        ON s.OrderID = o.OrderID
JOIN dbo.DeliveryZones dz ON o.ZoneID = dz.ZoneID
JOIN dbo.Warehouses w    ON o.WarehouseID = w.WarehouseID
WHERE s.DeliveryStatus = 'Delivered'
ORDER BY dz.Region, Rank_Within_Region;

------------------------------------------------------------------------

CREATE VIEW vw_LeadTime_Analysis AS
SELECT
    s.ShipmentID,
    o.OrderID,
    o.OrderPlacedAt,
    dz.Region,
    dz.ZoneName,
    dz.IsNEIndia,
    dz.SLA_Days,
    w.WarehouseName,
    w.City AS WarehouseCity,
    s.DeliveryStatus,
    s.CourierPartner,

    -- Stage durations
    DATEDIFF(HOUR, o.OrderPlacedAt, s.WarehouseDispatchedAt) 
        AS WH_Processing_Hrs,
    DATEDIFF(HOUR, s.WarehouseDispatchedAt, s.TransitHubDispatchedAt) 
        AS MidMile_Hrs,
    DATEDIFF(HOUR, s.TransitHubDispatchedAt, s.DeliveredAt) 
        AS LastMile_Hrs,
    DATEDIFF(HOUR, o.OrderPlacedAt, s.DeliveredAt) 
        AS Total_LeadTime_Hrs,

    -- SLA breach flag (SLA in days × 24 hrs)
    CASE 
        WHEN DATEDIFF(HOUR, o.OrderPlacedAt, s.DeliveredAt) > (dz.SLA_Days * 24) 
        THEN 'SLA Breached'
        ELSE 'Within SLA'
    END AS SLA_Status,

    -- Hours over SLA (positive = breached)
    DATEDIFF(HOUR, o.OrderPlacedAt, s.DeliveredAt) - (dz.SLA_Days * 24)
        AS Hrs_Over_SLA,

    -- Window: rank within region
    RANK() OVER (
        PARTITION BY dz.Region 
        ORDER BY DATEDIFF(HOUR, o.OrderPlacedAt, s.DeliveredAt) DESC
    ) AS Rank_Within_Region

FROM dbo.Shipments s
JOIN dbo.Orders o         ON s.OrderID = o.OrderID
JOIN dbo.DeliveryZones dz ON o.ZoneID = dz.ZoneID
JOIN dbo.Warehouses w     ON o.WarehouseID = w.WarehouseID
WHERE s.DeliveryStatus = 'Delivered';


SELECT * FROM vw_LeadTime_Analysis
ORDER BY Region, Total_LeadTime_Hrs DESC;


--------------------------------------------------------------------------------

-- Phase 3 — Bottleneck Analysis.

SELECT TOP 5
    w.WarehouseName,
    w.City,
    w.Region,
    COUNT(s.ShipmentID)                                             AS TotalShipments,
    ROUND(AVG(CAST(DATEDIFF(HOUR, o.OrderPlacedAt, 
        s.WarehouseDispatchedAt) AS FLOAT)), 1)                     AS Avg_WH_Processing_Hrs,
    ROUND(MAX(CAST(DATEDIFF(HOUR, o.OrderPlacedAt, 
        s.WarehouseDispatchedAt) AS FLOAT)), 1)                     AS Max_WH_Processing_Hrs,
    SUM(CASE WHEN s.DeliveryStatus = 'RTO' THEN 1 ELSE 0 END)      AS RTO_Count
FROM dbo.Shipments s
JOIN dbo.Orders o      ON s.OrderID = o.OrderID
JOIN dbo.Warehouses w  ON o.WarehouseID = w.WarehouseID
GROUP BY w.WarehouseName, w.City, w.Region
ORDER BY Avg_WH_Processing_Hrs DESC;


SELECT
    dz.ZoneName,
    dz.Region,
    dz.SLA_Days,
    COUNT(s.ShipmentID)                                             AS TotalShipments,
    ROUND(AVG(CAST(DATEDIFF(HOUR, s.WarehouseDispatchedAt,
        s.TransitHubDispatchedAt) AS FLOAT)), 1)                    AS Avg_MidMile_Hrs,
    ROUND(AVG(CAST(DATEDIFF(HOUR, o.OrderPlacedAt,
        s.DeliveredAt) AS FLOAT)), 1)                               AS Avg_Total_Hrs,
    SUM(CASE WHEN s.DeliveryStatus = 'RTO' THEN 1 ELSE 0 END)      AS RTO_Count,
    ROUND(CAST(SUM(CASE WHEN s.DeliveryStatus = 'RTO' 
        THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*) * 100, 1)          AS RTO_Pct
FROM dbo.Shipments s
JOIN dbo.Orders o         ON s.OrderID = o.OrderID
JOIN dbo.DeliveryZones dz ON o.ZoneID = dz.ZoneID
GROUP BY dz.ZoneName, dz.Region, dz.SLA_Days
ORDER BY Avg_MidMile_Hrs DESC;

----------------------------------------------------------

-- Phase 4 — Visualization.


-----------------------------------------------------------

-- Phase 5 - Executive PPT




USE SupplyChainDB;
SELECT 'DeliveryZones' AS TableName, COUNT(*) AS TotalRows FROM dbo.DeliveryZones
UNION ALL
SELECT 'Warehouses', COUNT(*) FROM dbo.Warehouses
UNION ALL
SELECT 'Orders', COUNT(*) FROM dbo.Orders
UNION ALL
SELECT 'Shipments', COUNT(*) FROM dbo.Shipments;