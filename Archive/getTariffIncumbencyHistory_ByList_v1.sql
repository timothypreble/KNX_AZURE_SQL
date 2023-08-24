SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/*
==============================================================================================================================
 Author:		Timothy Preble
 Create date:	08/17/2023
 Description:   Pull historical data & return Tariff Header Id, Tariff LaneId & KNX LaneId
 Confluence:	https://usxpress.atlassian.net/wiki/spaces/EN/pages/2760409089/Historical+Incumbency+Information
==============================================================================================================================
 Changes: 
 mm/dd/yyyy - Full Name			- Short description of changes
 08/17/2023 - Timothy Preble	- Initial Creation.
 08/21/2023 - Timothy Preble	- Update #Lanes Date Criteria.
==============================================================================================================================
 Indexes: 
 DatabaseName.Schema.IndexName

==============================================================================================================================
 Example: 
 DECLARE @i KNX_RFP_Request
INSERT INTO @i (
	        traceID
	    , laneId
		, companyCode
	    , customerNumber
	    , originCity
	    , originState
	    , originZip
	    , originMisc
	    , destinationCity
	    , destinationState
	    , destinationZip
	    , destinationMisc
	    , equipmentType
	    , customerMiles
	                )
VALUES
( 
  '6843CCA5-1FE6-4715-AE6D-643C06106DE3', 959, '01', 1045641, 'Stevenson'
  , 'AL', '', '', 'Corona', 'CA', '', '', 'V', 2054 )

EXEC [dbo].[getTariffIncumbencyHistory_ByList] @inbound =@i
==============================================================================================================================
*/
ALTER PROCEDURE [dbo].[getTariffIncumbencyHistory_ByList_v1] (
	@inbound KNX_RFP_Request READONLY
	) AS

BEGIN


/** TEST **/
-- DECLARE @inbound KNX_RFP_Request
--INSERT INTO @inbound (
--traceID , laneId , companyCode , customerNumber
--, originCity , originState , originZip
--, originMisc , destinationCity , destinationState , destinationZip
--, destinationMisc , equipmentType , customerMiles )
--VALUES
--( '6843CCA5-1FE6-4715-AE6D-643C06106DE3', 959, '01', 1045641, 'Stevenson'
--  , 'AL', '', '', 'Corona', 'CA', '', '', 'V', 2054 )
/** TEST **/

DECLARE @contractDate DATE = GETDATE(); --'2023-08-18'
DECLARE @historicalDate DATE = DATEADD(MONTH,-6,@contractDate); --'2023-02-18'
DECLARE @BillTO TABLE(CompanyCode VARCHAR(4) NOT NULL, customerNumber DECIMAL(7,0) NOT NULL)
INSERT INTO @BillTo
SELECT DISTINCT companyCode,customerNumber FROM @inbound
--SELECT * FROM @BillTO;

/* * * * Create temp #Lanes table to store history * * * */
DROP TABLE IF EXISTS #Lanes
CREATE TABLE [#Lanes]
(
processed VARCHAR(100) NULL,
[KNX_Lane_Id] INT NULL,
[isActive] BIT NOT NULL, --Active =1, Historical = 0
[companyCode] VARCHAR(4) NOT NULL,
[customerNumber] DECIMAL(7,0) NOT NULL,
[equipmentType] VARCHAR(50) NULL,
[pricingEntity] VARCHAR(30) NULL,
[serviceEntity] VARCHAR(30) NULL,
[o_City] VARCHAR(25) NULL,
[o_State] VARCHAR(25) NULL,
[o_ZipCode] VARCHAR(200) NULL,
--[o_Miscellaneous] VARCHAR(200),

[d_City] VARCHAR(25) NULL,
[d_State] VARCHAR(25) NULL,
[d_ZipCode] VARCHAR(200) NULL,
--[d_Miscellaneous] VARCHAR(200),
tariff_lane_id INT NULL,
[USX_Lane_Id] INT NOT NULL,
xone_knx_lane_id INT NULL,
usxi_knx_lane_id INT NULL,
[effectiveOn] DATE NULL,
[expiresOn] DATE NULL,
[tariff_Header_Id] INT NOT NULL
);

/** Get all lanes for the customer in the inbound playload & store in #Lanes **/
INSERT INTO #Lanes
(
    processed,
    isActive,
    companyCode,
    customerNumber,
    equipmentType,
    pricingEntity,
    serviceEntity,
    o_City,
    o_State,
    o_ZipCode,
    d_City,
    d_State,
    d_ZipCode,
    tariff_lane_id,
    USX_Lane_Id,
    xone_knx_lane_id,
    usxi_knx_lane_id,
    effectiveOn,
    expiresOn,
    tariff_Header_Id
)

SELECT NULL AS processed,
CASE WHEN @contractDate BETWEEN tl.lane_effective_date AND TL.lane_expiration_date THEN 1
ELSE 0 END  AS [isActive],
       th.company_id AS [companyCode],				--Passed In
       th.customer_bill_to_id AS [customerNumber],	--Passed In
       th.equipment_type AS [equipmentType],		--Passed In

       TH.pricing_entity AS [pricingEntity],		--:  "Brokerage",  //Brokerage | Dedicated | OTR | Any
       TH.service_entity AS [serviceEntity],		--: "SOLO", //SOLO | TEAM | ANY
--origin
       TL.ct_from_city AS [o_City],					--Passed In
       TL.ct_from_state AS [o_State],				--Passed In
       TL.ct_from_zip AS [o_ZipCode],				--Passed In
       --AS [o_Miscellaneous],						--Passed In
--destination
       TL.ct_to_city AS [d_City],					--Passed In
       TL.ct_to_state AS [d_State],					--Passed In
       TL.ct_to_zip AS [d_ZipCode],					--Passed In
       -- AS [d_Miscellaneous],						--Passed In

       tl.tariff_lane_id AS tariff_lane_id,						--Not sure about this since we are going to represent both OTR & BRK on the same row.  Are those Diff lane IDs?
	  tl.lane_id AS [USX_Lane_Id],

--USXI
	NULL AS xone_knx_lane_id,
	NULL AS usxiknx_lane_id,
	   tl.lane_effective_date AS [effectiveOn],
       tl.lane_expiration_date AS [expiresOn],
       
	   th.tariff_header_Id

FROM [dbo].[tariff_header] AS TH	
  JOIN [dbo].[tariff_lane] AS TL ON TH.tariff_header_Id = TL.tariff_header_Id

  JOIN @BillTO  AS b ON b.companyCode = th.company_id AND b.customerNumber =th.customer_bill_to_id
  WHERE 
		th.pricing_entity IN ('ANY','OTR','BRK')
  AND	TH.service_entity IN ('ANY', 'SOLO', 'TEAM')
  AND	TH.isdeleted=0
  --AND	DATEADD(MONTH,-6,@contractDate) BETWEEN tl.lane_effective_date AND TL.lane_expiration_date
  AND @contractDate BETWEEN tl.lane_effective_date AND TL.lane_expiration_date
AND (tl.lane_effective_date>=@historicalDate AND tl.lane_expiration_date<=@historicalDate)
OR  tl.lane_expiration_date>=@contractDate

/* * * * Create Temp outbound table * * * */
DROP TABLE IF EXISTS #Data;
CREATE TABLE [#DATA]
(
processed VARCHAR(50) NULL,
[bidId] VARCHAR(100),
[companyCode] VARCHAR(4) NOT NULL,
[customerNumber] INT NOT NULL,
[equipmentType] CHAR(1),
--[equipmentNeeds] VARCHAR(100),
[knx_LaneId] INT NOT NULL,
[customerMiles] INT,
[pricingEntity] VARCHAR(100),
[serviceEntity] VARCHAR(100),
[o_City] VARCHAR(100),
[o_State] CHAR(2),
[o_Zip] VARCHAR(100),
[o_ZipCode] VARCHAR(100),
[o_Miscellaneous] VARCHAR(100),
[d_City] VARCHAR(100),
[d_State] CHAR(2),
[d_zip] VARCHAR(100),
[d_ZipCode] VARCHAR(100),
[d_Miscellaneous] VARCHAR(100),
--[laneId] INT,
--[originMetro] VARCHAR(100),
--[destinationMetro] VARCHAR(100),
[usxi_laneId] VARCHAR(100),
--[usxi_Tariff_Lane_Id]
[usxi_committedVolume] INT,
--[usxi_current6MonthOrderVolume] INT,
--[usxi_gmFirstName] VARCHAR(100),
--[usxi_gmLastName] VARCHAR(100),
--[usxi_gmEmail] VARCHAR(100),
[usxi_effectiveOn] DATETIME,
[usxi_expiresOn] DATETIME,
[usxi_flat]DECIMAL(18,3),
[usxi_flatCalculated] DECIMAL(18,3),
[usxi_flatRatePerMile] DECIMAL(18,3),
[usxi_minimumFlatRate] DECIMAL(18,3),
[usxi_ratePerMile] DECIMAL(18,3),
[usxi_rateType] VARCHAR(100),
[usxi_contractType] VARCHAR(100),
[usxi_Tariff_Header_Id] INT,

[xone_laneId] VARCHAR(100),
[xone_committedVolumne] INT,
--[xone_current6MonthOrderVolume] INT,
--[xone_gmFirstName] VARCHAR(100),
--[xone_gmLastName] VARCHAR(100),
--[xone_gmEmail] VARCHAR(100),
[xone_effectiveOn] DATETIME,
[xone_expiresOn] DATETIME,
[xone_flat] DECIMAL(18,3),
[xone_flatCalculated] DECIMAL(18,3),
[xone_flatRatePerMile] DECIMAL(18,3),
[xone_minimumFlatRate] DECIMAL(18,3),
[xone_ratePerMile] DECIMAL(18,3),
[xone_rateType] VARCHAR(100),
[xone_contractType] VARCHAR(100),
[xone_Tariff_Header_Id] INT
)

/* * * * Fill temp outbound table with INBOUND RFP * * * */
INSERT INTO #DATA
(
    companyCode,
    customerNumber,
    equipmentType,
    knx_LaneId,
    o_City,
    o_State,
	o_Zip,
    o_ZipCode,
    o_Miscellaneous,
    d_City,
    d_State,
	d_zip,
    d_ZipCode,
    d_Miscellaneous,
    customerMiles
)
SELECT 
       
       companyCode,
       customerNumber,
       equipmentType,
       
	   laneId,
	   originCity,
       originState,
       originZip,
	   COALESCE(i.originZip,i.originMisc),
       originMisc,
       destinationCity,
       destinationState,
       destinationZip,
	   COALESCE(i.destinationZip,i.destinationMisc),
       destinationMisc,
       customerMiles
FROM @inbound i;

/* * * * What Service Entity is in #Lanes* * * */
DECLARE @isSOLO CHAR(4) = (SELECT TOP(1) 'SOLO' FROM #Lanes WHERE serviceEntity='SOLO');
DECLARE	@isTEAM CHAR(4) = (SELECT TOP(1) 'TEAM' FROM #Lanes WHERE serviceEntity='TEAM');
DECLARE @isANY_SERVICE CHAR(3) = (SELECT TOP(1) 'ANY' FROM #Lanes WHERE serviceEntity='ANY');

/* * * * Return Service / Pricing Entity * * * */
DECLARE @service_entity VARCHAR(4) = COALESCE(@isSOLO,@isANY_SERVICE,@isTEAM);


/* * * * Process GEOG Matching * * * */
--•    Level 1 -  Zip to zip
UPDATE l
	SET processed='zip-zip',
	l.xone_knx_lane_id = CASE  WHEN l.pricingEntity='BRK' AND l.xone_knx_lane_id IS null THEN d.knx_LaneId END,
	l.usxi_knx_lane_id = CASE WHEN l.pricingEntity <>'BRK' AND l.usxi_knx_lane_id IS null THEN d.knx_LaneId END
FROM #DATA d 
JOIN #Lanes l ON d.o_ZipCode =l.o_ZipCode AND d.d_ZipCode=l.d_ZipCode 
   WHERE l.serviceEntity=@service_entity  
  
--•    Level 2 -  Zip to city/state
UPDATE l
	SET processed ='zip-CityState',
	l.xone_knx_lane_id = CASE  WHEN l.pricingEntity='BRK' AND l.xone_knx_lane_id IS null THEN d.knx_LaneId END,
	l.usxi_knx_lane_id = CASE WHEN l.pricingEntity <>'BRK' AND l.usxi_knx_lane_id IS null THEN d.knx_LaneId END
		
FROM #DATA d 
JOIN #Lanes l ON d.o_ZipCode =l.o_ZipCode AND (d.d_City = l.d_City AND d.d_State=l.d_State) 
   WHERE l.serviceEntity=@service_entity  

 --•    Level 3 - City/state to zip
 	UPDATE l
	SET processed='CityState-Zip',
		l.xone_knx_lane_id = CASE  WHEN l.pricingEntity='BRK' AND l.xone_knx_lane_id IS null THEN d.knx_LaneId END,
	    l.usxi_knx_lane_id = CASE WHEN l.pricingEntity <>'BRK' AND l.usxi_knx_lane_id IS null THEN d.knx_LaneId END
		
FROM #DATA d 
JOIN #Lanes l ON (d.o_City=l.o_City AND d.o_State=l.o_State) AND d.d_ZipCode=l.d_ZipCode
  WHERE l.serviceEntity=@service_entity  

--•    Level 4 - City/state to city/state
	UPDATE l
	SET processed='CityState-CityState',
		l.xone_knx_lane_id = CASE  WHEN l.pricingEntity='BRK' AND l.xone_knx_lane_id IS null THEN d.knx_LaneId END,
	    l.usxi_knx_lane_id = CASE WHEN l.pricingEntity <>'BRK' AND l.usxi_knx_lane_id IS null THEN d.knx_LaneId END
		
FROM #DATA d 
  JOIN #Lanes l ON (d.o_City =l.o_City AND d.o_State=l.o_State) AND (d.d_City=l.d_City AND d.d_State=l.d_State) 
  WHERE l.serviceEntity=@service_entity
  



 --•    Level 5 - Zip to zone
	UPDATE l
	SET processed = 'Zip-Zone',
		l.xone_knx_lane_id = CASE  WHEN l.pricingEntity='BRK' AND l.xone_knx_lane_id IS null THEN d.knx_LaneId END,
	    l.usxi_knx_lane_id = CASE WHEN l.pricingEntity <>'BRK' AND l.usxi_knx_lane_id IS null THEN d.knx_LaneId END
		
  FROM #DATA d 
  JOIN #Lanes l ON d.o_ZipCode =l.o_ZipCode AND LEFT(d.d_ZipCode,3)=LEFT(l.d_ZipCode,3) 
    WHERE l.serviceEntity=@service_entity  

--•    Level 6 - Zone to zip
	UPDATE l
	SET processed='Zone-Zip',
		l.xone_knx_lane_id = CASE  WHEN l.pricingEntity='BRK' AND l.xone_knx_lane_id IS null THEN d.knx_LaneId END,
	    l.usxi_knx_lane_id = CASE WHEN l.pricingEntity <>'BRK' AND l.usxi_knx_lane_id IS null THEN d.knx_LaneId END
		
  FROM #DATA d 
  JOIN #Lanes l ON LEFT(d.o_ZipCode,3) =LEFT(l.o_ZipCode,3) AND d.d_ZipCode=l.d_ZipCode 
    WHERE l.serviceEntity=@service_entity  

--•    Level 7 - City/state to zone
	UPDATE l
	SET processed='CityState-Zone',
		l.xone_knx_lane_id = CASE  WHEN l.pricingEntity='BRK' AND l.xone_knx_lane_id IS null THEN d.knx_LaneId END,
	    l.usxi_knx_lane_id = CASE WHEN l.pricingEntity <>'BRK' AND l.usxi_knx_lane_id IS null THEN d.knx_LaneId END
		
  FROM #DATA d 
  JOIN #Lanes l ON (d.o_City=l.o_City AND d.o_State=l.o_State) AND LEFT(d.d_ZipCode,3) = LEFT(l.d_ZipCode,3) 
    WHERE l.serviceEntity=@service_entity  

 --•    Level 8 - Zone to city/state
	UPDATE l
	SET processed='Zone-CityState',
		l.xone_knx_lane_id = CASE  WHEN l.pricingEntity='BRK' AND l.xone_knx_lane_id IS null THEN d.knx_LaneId END,
	    l.usxi_knx_lane_id = CASE WHEN l.pricingEntity <>'BRK' AND l.usxi_knx_lane_id IS null THEN d.knx_LaneId END
		
  FROM #DATA d  
  JOIN #Lanes l ON LEFT(d.o_ZipCode,3) =LEFT(l.o_ZipCode,3) AND (d.d_City = l.o_City and d.d_State=l.d_State) 
    WHERE l.serviceEntity=@service_entity  

--•    Level 9 - Zone to zone
	UPDATE l
	SET processed='Zone-Zone',
		l.xone_knx_lane_id = CASE  WHEN l.pricingEntity='BRK' AND l.xone_knx_lane_id IS null THEN d.knx_LaneId END,
	    l.usxi_knx_lane_id = CASE WHEN l.pricingEntity <>'BRK' AND l.usxi_knx_lane_id IS null THEN d.knx_LaneId END
		
  FROM #DATA d  
  JOIN #Lanes l ON LEFT(d.o_ZipCode,3) =LEFT(l.o_ZipCode,3) AND LEFT(d.d_ZipCode,3)=LEFT(l.d_ZipCode,3)
    WHERE l.serviceEntity=@service_entity  

--•    Level 10 - Zip to state
	UPDATE l
	SET processed='Zip-State',
		l.xone_knx_lane_id = CASE  WHEN l.pricingEntity='BRK' AND l.xone_knx_lane_id IS null THEN d.knx_LaneId END,
	    l.usxi_knx_lane_id = CASE WHEN l.pricingEntity <>'BRK' AND l.usxi_knx_lane_id IS null THEN d.knx_LaneId END
	
  FROM #DATA d  
  JOIN #Lanes l ON d.o_ZipCode=l.o_ZipCode AND d.d_State = l.d_State 
    WHERE l.d_City IS NULL AND l.d_ZipCode IS null 
	AND l.serviceEntity=@service_entity  

--•    Level 11- State to zip
	UPDATE l
	SET processed='State-Zip',
		l.xone_knx_lane_id = CASE  WHEN l.pricingEntity='BRK' AND l.xone_knx_lane_id IS null THEN d.knx_LaneId END,
	    l.usxi_knx_lane_id = CASE WHEN l.pricingEntity <>'BRK' AND l.usxi_knx_lane_id IS null THEN d.knx_LaneId END
		
  FROM #DATA d 
  JOIN #Lanes l ON d.o_State=l.o_State AND d.d_ZipCode=l.d_ZipCode 
    WHERE l.o_City IS NULL AND l.o_ZipCode IS NULL 
	AND l.serviceEntity=@service_entity  

  --•    Level 12 - City/state to state
	UPDATE l
	SET processed='CityState-State',
		l.xone_knx_lane_id = CASE  WHEN l.pricingEntity='BRK' AND l.xone_knx_lane_id IS null THEN d.knx_LaneId END,
	    l.usxi_knx_lane_id = CASE WHEN l.pricingEntity <>'BRK' AND l.usxi_knx_lane_id IS null THEN d.knx_LaneId END
	--SELECT *
  FROM #DATA d 
  JOIN #Lanes l ON (d.o_City=l.o_City AND d.o_State=l.o_State) AND d.d_State = l.d_State 
    WHERE l.d_City is NULL AND l.d_ZipCode IS NULL 
	AND l.serviceEntity=@service_entity  

  --•    Level 13 - State to city/State
	UPDATE l
	SET processed='State-CityState',
		l.xone_knx_lane_id = CASE  WHEN l.pricingEntity='BRK' AND l.xone_knx_lane_id IS null THEN d.knx_LaneId END,
	    l.usxi_knx_lane_id = CASE WHEN l.pricingEntity <>'BRK' AND l.usxi_knx_lane_id IS null THEN d.knx_LaneId END
  --SELECT *
  FROM #DATA d 
  JOIN #Lanes l ON d.o_State=l.o_State AND (d.d_City=l.d_City AND d.d_State=l.d_State) 
    WHERE l.o_City IS NULL AND l.o_ZipCode IS NULL
	AND l.serviceEntity=@service_entity  

  --•    Level 14 - Zone to state
	UPDATE l
	SET processed='Zone-State',
		l.xone_knx_lane_id = CASE  WHEN l.pricingEntity='BRK' AND l.xone_knx_lane_id IS null THEN d.knx_LaneId END,
	    l.usxi_knx_lane_id = CASE WHEN l.pricingEntity <>'BRK' AND l.usxi_knx_lane_id IS null THEN d.knx_LaneId END
--SELECT *	
  FROM #DATA d 
  JOIN #Lanes l ON LEFT(d.o_ZipCode,3) = LEFT(l.o_ZipCode,3) AND d.d_State=l.d_State 
    WHERE d.d_City IS NULL AND d.d_zip IS null 
	AND l.serviceEntity=@service_entity  

  --•    Level 15 - State to zone
	UPDATE l
	SET processed='State-Zone',
		l.xone_knx_lane_id = CASE  WHEN l.pricingEntity='BRK' AND l.xone_knx_lane_id IS null THEN d.knx_LaneId END,
	    l.usxi_knx_lane_id = CASE WHEN l.pricingEntity <>'BRK' AND l.usxi_knx_lane_id IS null THEN d.knx_LaneId END
  FROM #DATA d 
  JOIN #Lanes l ON d.o_State=l.o_State AND LEFT(d.d_ZipCode,3) = LEFT(l.d_ZipCode,3) 
    WHERE l.o_City IS NULL AND l.o_ZipCode IS NULL 
	AND l.serviceEntity=@service_entity  

--•    Level 16 -  State to state
	UPDATE l
	SET processed='State-State',
		l.xone_knx_lane_id = CASE  WHEN l.pricingEntity='BRK' AND l.xone_knx_lane_id IS null THEN d.knx_LaneId END,
	    l.usxi_knx_lane_id = CASE WHEN l.pricingEntity <>'BRK' AND l.usxi_knx_lane_id IS null THEN d.knx_LaneId END
  FROM #DATA d 
JOIN #Lanes l ON d.o_State=l.o_State  AND d.d_State=l.d_State  
where		l.o_ZipCode IS NULL AND l.o_City IS NULL
		AND l.d_ZipCode IS NULL AND l.d_City IS null
		AND l.serviceEntity=@service_entity  


/* Merge USXI & XONE into a single */
;WITH _usxi AS (
SELECT distinct l.companyCode,l.customerNumber
,l.tariff_Header_Id,l.USX_Lane_Id,usxi_knx_lane_id AS knx_Lane_Id
--,l.xone_knx_lane_id
 FROM #Lanes l
 where --l.xone_knx_lane_id IS NOT NULL OR
	   l.usxi_knx_lane_id IS NOT NULL
),
_xone AS (
SELECT distinct l.companyCode,l.customerNumber
,l.tariff_Header_Id,l.USX_Lane_Id
--,usxi_knx_lane_id
,l.xone_knx_lane_id AS knx_Lane_Id
 FROM #Lanes l
 where l.xone_knx_lane_id IS NOT NULL
	--OR l.usxi_knx_lane_id IS NOT NULL
)
SELECT *
	   FROM _usxi
UNION
SELECT *
	   FROM _xone



		/* * * * combine all data into a single table & return a distinct list * * * */
 /*DECLARE @Outbound TABLE 
(
companyCode VARCHAR(4),
customerNumber DECIMAL(7,0),
tariff_header_Id int,
USX_Lane_Id INT,
KNX_Lane_Id INT
)
INSERT INTO @Outbound
(
    companyCode,
    customerNumber,
	tariff_header_Id,
    USX_Lane_Id,
    KNX_Lane_Id
)

 SELECT distinct l.companyCode,l.customerNumber,l.tariff_Header_Id,l.USX_Lane_Id,xone_knx_lane_id
 FROM #Lanes l
 WHERE l.xone_knx_lane_id IS NOT NULL

UNION ALL
SELECT distinct l.companyCode,l.customerNumber,l.tariff_Header_Id,l.USX_Lane_Id,usxi_knx_lane_id
 FROM #Lanes l
 WHERE l.usxi_knx_lane_id IS NOT null
 
 SELECT DISTINCT companyCode,
        customerNumber,
        tariff_header_Id,
        USX_Lane_Id,
        KNX_Lane_Id
 FROM @Outbound
 ORDER BY companyCode,customerNumber,tariff_header_Id,USX_Lane_Id


 SELECT l.processed, l.companyCode,l.customerNumber,l.tariff_Header_Id,l.USX_Lane_Id
 ,xone_knx_lane_id,usxi_knx_lane_id 
 ,d.o_City,d.o_State,d.o_Zip,d.d_City,d.d_State,d.d_zip
 FROM #Lanes l
 LEFT JOIN #DATA d 
 ON l.usxi_knx_lane_id = d.knx_LaneId
 WHERE usxi_knx_lane_id IS NOT NULL OR xone_knx_lane_id IS NOT NULL
 --l.usxi_knx_lane_id=1156
 order BY l.tariff_lane_id,l.USX_Lane_Id;


 SELECT *
 FROM #Lanes
 WHERE o_City='Hopewell'
 and d_State='GA'

 SELECT *
 FROM dbo.tariff_header th
 JOIN dbo.tariff_lane tl ON tl.tariff_header_Id = th.tariff_header_Id
 WHERE th.tariff_header_Id = 3082 AND tl.lane_id=483
*/
END
GO
