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
 08/22/2023 - Timothy Preble	- Added classification_type to update statements.
 08/24/2023 - Timothy Preble	- VERSION 5
									Added Tariff join criteria from JeffP
									JOIN [dbo].[TARIFF_CROSS_REFERENCE] TCR ON th.customer_bill_to_id = tcr.TARIFF_CONT_BILTO_ID 
									AND CONCAT(th.tariff,'-',TH.tariff_item) = tcr.TARIFF_CUST_BUS_UNIT
 08/25/2023 - Timothy Preble	- Fixed casing on final results to match what has been documented on Confluence.
 09/26/2023 - Timothy Preble	- #Lanes OR critera was outside of parenthesis, corrected. 
 10/03/2023 - Timothy Preble	- Changed @currentDate to @currentDate.
									Removed commented out code from bottom of procedure.
									Added the "Frakie Logic" to the bottom of procedure.
									Revised "WHERE" criteria to include active and inactive within the 6 month range.
										https://usxpress.atlassian.net/browse/KPS-63
10/10/2023 - Timothy Preble     - refactored to return all historical lane matches for passed in rfp lanes
                                    Removed all Brokerag / Non-Brokerage logic.  This proc will return the Tariff Header/Lane IDs
                                        The incumbency proc will determine the incumbent pricing entity
                                        The historical order proc will determine the pricing entity that actually serviced the load
									
									Remove the LEFT(xyz, 3) logic from all matches.  This will ensure that if the rfp contains a range 000-001
										will try and match.

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
( '6843CCA5-1FE6-4715-AE6D-643C06106DE3', 959, '01', 1045641, 'Stevenson', 'AL', '', '', 'Corona', 'CA', '', '', 'V', 2054 )
,(NULL, 3,'01',1302773,'Fairburn','GA',NULL,NULL, 'Newnan', 'GA', NULL,NULL, NULL, '939')
EXEC [dbo].[getTariffIncumbencyHistory_ByList] @inbound =@i
==============================================================================================================================
*/
ALTER PROCEDURE [dbo].[getTariffIncumbencyHistory_ByList] (
	@inbound KNX_RFP_Request READONLY
	) AS

BEGIN
/** TEST **/
/*
DECLARE @inbound KNX_RFP_Request
INSERT INTO @inbound (
laneId , companyCode , customerNumber
, originCity , originState, originZip, originMisc 
, destinationCity , destinationState , destinationZip, destinationMisc 
, equipmentType , customerMiles )
VALUES


--•    Level 1 -  Zip to zip ('5-Zip To 5-Zip')
	(1,'01', 1063192,'Murfreesboro','TN', '37130',NULL,'Neelys Landing','MO','63755',NULL,NULL,1111), --3Records (2998/34 - 3330/24 - 3559/16)

--•    Level 2 -  Zip to city/state ('5-Zip To City')
	(2,'01', 973983, NULL,NULL,'92374',NULL,'DURANT', 'OK', NULL, NULL, NULL,2222), 	--1432/23

--•    Level 3 - City/state to zip ('City To 5-Zip')
	(3,'01',1116153,'NACOGDOCHES','TX',NULL,NULL,NULL,NULL,'76712',NULL,NULL,3333), --(3181/6320 active )
	-- (3,'01', 975812,'Chattanooga','TN',NULL,NULL,NULL,NULL,'33810',NULL,NULL,3333)

--•    Level 4 - City/state to city/state ('City To City')
	(4,'01', 1045641,'Jacksonville','Fl',NULL,NULL,'Chattanooga','TN',NULL,NULL,NULL,4444),	--2Records (3397/160 active - 3397/162 inactive)

--•    Level 5 - Zip to zone ('5-Zip To 3-Zip' )
	(5,'01',1259726,NULL,NULL,'45331',NULL,NULL,NULL,NULL,'305',NULL,5555), -- 3Recrods (3276,10 inactive - 3276/107 inactive - 3694/41 active)
	(5,'01',1259726,null,null,'03031',null,null,null,NULL,'070-088',null,5555), --3Records (3276/9 inactive - 3276/98 inactive - 3694/23 active)

--•    Level 6 - Zone to zip ('3-Zip To 5-Zip')
	(6, '01', 1259726, NULL, 'GA', '305', NULL, NULL, 'GA', '30253', NULL, NULL, 6666), --3Records (3276/31 inactive - 3276/79 inactive - 3694/13 active)
	(6, '01', 1259726, NULL, 'CA', NULL, '900-917', NULL, 'AZ', '85043', NULL, NULL, 6666), --3Records (3276/28 inactive - 3276/76 inactive - 3694/10 active)

--•    Level 7 - City/state to zone ('City To 3-Zip')
	(7,'01', 712514,'Jacksonville','FL',NULL,NULL,NULL,NULL,NULL,'704',NULL,7), --1269/1084
	(7,'01', 712514,'Jacksonville','FL',NULL,NULL,NULL,NULL,NULL,'705-707',NULL,7), --1269/1085 

--•    Level 8 - Zone to city/state ('3-Zip To City')
	(8, '01', 973983,NULL,NULL,NULL,'307','APPLE VLY', 'CA', NULL,NULL,NULL,555), -- 1435/17
	(8,'01', 975812,Null,null,null,'324-325','Chattanooga','TN',NULL,NULL,null,4321), --(784/14)

--•    Level 9 - Zone to zone ('3-Zip To 3-Zip')
	( 9, '01', 1259726, NULL, 'IA', '527', NULL, NULL, 'GA', '305', NULL, NULL, NULL ), -- 3Records (3275/4 inactive - 3275/53 inactive - 3692/7 active )
	( 9, '01', 1259726, NULL, 'IA', '527', NULL, NULL, 'OH', '430-432', NULL, NULL, NULL ),	--: ###### 3Records verify & log IDs #### :--
	-- ( 9, '01', 1259726, NULL, 'IL', '600-608', NULL, NULL, 'CA', '900-917', NULL, NULL, NULL ),		--3693/5	--TEAM

--•    Level 10 - Zip to state ('5-Zip To State')
	( 10, '01', 1116542, NULL, 'CA', '95418', NULL, NULL, 'AR', NULL, NULL, NULL, NULL ),	--(3480/1441)

--•    Level 11- State to zip ('State To 5-Zip' )
	( 11, '01', 1116153, NULL, 'ON', NULL, NULL, NULL, 'NY', '13340', NULL, NULL, NULL ),	--(3181/7128)

--•    Level 12 - City/state to state ('City To State')
	( 12, '01', 744714, 'ALACHUA', 'FL', NULL, NULL, NULL, 'TN', NULL, NULL, NULL, NULL ),
    ( 12, '01', 138900, 'EL PASO', 'TX', NULL, NULL, NULL, 'BC', NULL, NULL, NULL, NULL ),   --(QA: 2336/30463)

--•    Level 13 - State to city/State ('State To City' )
	( 13, '01', 975812, NULL, 'AR', NULL, NULL, 'CHATTANOOGA', 'TN', NULL, NULL, NULL, NULL ),

--•    Level 14 - Zone to state ('3-Zip To State' )
	( 14, '01', 138900, NULL, 'AZ', '864', NULL, NULL, 'NS', NULL, NULL, NULL, NULL ),	--2Records (2336/1656 inactive - 3463/1245 active)

--•    Level 15 - State to zone ('State To 3-Zip' )
	( 15, '01', 138900, NULL, 'AB', NULL, NULL, NULL, 'AZ', '864', NULL, NULL, NULL ),	--2Records (2336/11 inactive - 3463/11 active)

--•    Level 16 -  State to state ('State To State'  )
	( 16, '01', 1116542, NULL, 'NC', NULL, NULL, NULL, 'AR', NULL, NULL, NULL, NULL )	--879/2777
*/
/** TEST **/

DECLARE @currentDate DATE = GETDATE();
DECLARE @historicalDate DATE = DATEADD(MONTH,-6,@currentDate); --'2023-02-18'
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
	,classification_type VARCHAR(100) NULL
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
    tariff_Header_Id,
	classification_type
)

SELECT distinct
	NULL AS processed,
	CASE WHEN @currentDate BETWEEN tl.lane_effective_date AND TL.lane_expiration_date THEN 1
	ELSE 0 END  AS [isActive],
	th.company_id AS [companyCode],				--Passed In
	th.customer_bill_to_id AS [customerNumber],	--Passed In
	th.equipment_type AS [equipmentType],		--Passed In
	TH.pricing_entity AS [pricingEntity],		--:  "Brokerage",  //Brokerage | Dedicated | OTR | Any
	TH.service_entity AS [serviceEntity],		--: "SOLO", //SOLO | TEAM | ANY
--origin
	TL.ct_from_city AS [o_City],				--Passed In
	TL.ct_from_state AS [o_State],				--Passed In
	TL.ct_from_zip AS [o_ZipCode],				--Passed In
	--AS [o_Miscellaneous],						--Passed In
--destination
	TL.ct_to_city AS [d_City],					--Passed In
    TL.ct_to_state AS [d_State],				--Passed In
    TL.ct_to_zip AS [d_ZipCode],				--Passed In
    -- AS [d_Miscellaneous],					--Passed In

	tl.tariff_lane_id AS tariff_lane_id,	
	tl.lane_id AS [USX_Lane_Id],
--USXI
	NULL AS xone_knx_lane_id,
	NULL AS usxiknx_lane_id,
	tl.lane_effective_date AS [effectiveOn],
	tl.lane_expiration_date AS [expiresOn],
       
	th.tariff_header_Id,
	tl.classification_type
FROM [dbo].[tariff_header] AS TH	
	JOIN [dbo].[TARIFF_CROSS_REFERENCE] TCR ON th.customer_bill_to_id = tcr.TARIFF_CONT_BILTO_ID	--20230824:TP Added 
		AND CONCAT(th.tariff,'-',TH.tariff_item) = tcr.TARIFF_CUST_BUS_UNIT							--20230824:TP Added 
  JOIN [dbo].[tariff_lane] AS TL ON TH.tariff_header_Id = TL.tariff_header_Id AND tl.isdeleted=0
  JOIN @BillTO  AS b ON b.companyCode = th.company_id 
					AND b.customerNumber = tcr.TARIFF_BILL_TO			--20230824:TP Added
WHERE 
		th.pricing_entity IN ('ANY','OTR','BRK')
  AND	TH.service_entity IN ('ANY', 'SOLO', 'TEAM')
  AND	TH.isdeleted=0
-- 20231003:TP Added
  AND
	(
		( @historicalDate BETWEEN tl.lane_effective_date AND tl.lane_expiration_date )
		OR ( tl.lane_expiration_date >= @currentDate )
		OR ( tl.lane_effective_date  BETWEEN @historicalDate AND @currentDate )
	);


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
-- SELECT  @service_entity --,@currentDate,@historicalDate

-- SELECT o_ZipCode,d_ZipCode, * FROM #data d where customerNumber=1259726
-- select o_ZipCode,d_ZipCode, * from #Lanes where customernumber=1259726
-- and o_zipcode = '03031'
-- and d_zipCode = '070-088'

-- SELECT l.classification_type
-- ,d.o_ZipCode ,l.o_ZipCode , d.d_ZipCode,l.d_ZipCode
-- , *
-- FROM #DATA d 
--   JOIN #Lanes l ON d.companyCode = l.companyCode and d.customerNumber=l.customerNumber AND 
-- d.o_ZipCode =l.o_ZipCode AND d.d_ZipCode=l.d_ZipCode AND l.classification_type='5-Zip To 3-Zip' 
--     WHERE l.serviceEntity=@service_entity  

/* * * * Process GEOG Matching * * * */
--•    Level 1 -  Zip to zip
UPDATE l SET l.processed=l.classification_type,l.KNX_Lane_Id=d.knx_LaneId
	-- d.xone_laneId = CASE  WHEN l.pricingEntity='BRK' AND d.xone_laneId IS null THEN l.USX_Lane_Id END,
	-- d.usxi_laneId = CASE WHEN l.pricingEntity <>'BRK' AND d.usxi_laneId IS null THEN l.USX_Lane_Id END,
	-- d.xone_Tariff_Header_Id = CASE  WHEN l.pricingEntity='BRK' AND d.xone_Tariff_Header_Id IS null THEN l.tariff_Header_Id END,
	-- d.usxi_Tariff_Header_Id = CASE WHEN l.pricingEntity <>'BRK' AND d.usxi_Tariff_Header_Id IS null THEN l.tariff_Header_Id END
FROM #DATA d 
JOIN #Lanes l ON d.companyCode = l.companyCode and d.customerNumber=l.customerNumber AND 
d.o_ZipCode =l.o_ZipCode AND d.d_ZipCode=l.d_ZipCode AND l.classification_type='5-Zip To 5-Zip'
   WHERE l.serviceEntity=@service_entity  

--•    Level 2 -  Zip to city/state
UPDATE l SET l.processed=l.classification_type,l.KNX_Lane_Id=d.knx_LaneId
	-- d.xone_laneId = CASE  WHEN l.pricingEntity='BRK' AND d.xone_laneId IS null THEN l.USX_Lane_Id END,
	-- d.usxi_laneId = CASE WHEN l.pricingEntity <>'BRK' AND d.usxi_laneId IS null THEN l.USX_Lane_Id END,
	-- d.xone_Tariff_Header_Id = CASE  WHEN l.pricingEntity='BRK' AND d.xone_Tariff_Header_Id IS null THEN l.tariff_Header_Id END,
	-- d.usxi_Tariff_Header_Id = CASE WHEN l.pricingEntity <>'BRK' AND d.usxi_Tariff_Header_Id IS null THEN l.tariff_Header_Id END
FROM #DATA d 
JOIN #Lanes l ON d.companyCode = l.companyCode and d.customerNumber=l.customerNumber AND 
d.o_ZipCode =l.o_ZipCode AND (d.d_City = l.d_City AND d.d_State=l.d_State) AND l.classification_type='5-Zip To City'
   WHERE l.serviceEntity=@service_entity  

 --•    Level 3 - City/state to zip
 	UPDATE l SET l.processed=l.classification_type,l.KNX_Lane_Id=d.knx_LaneId
	-- SET l.processed='City To 5-Zip'
	-- d.xone_laneId = CASE  WHEN l.pricingEntity='BRK' AND d.xone_laneId IS null THEN l.USX_Lane_Id END,
	-- d.usxi_laneId = CASE WHEN l.pricingEntity <>'BRK' AND d.usxi_laneId IS null THEN l.USX_Lane_Id END,
	-- d.xone_Tariff_Header_Id = CASE  WHEN l.pricingEntity='BRK' AND d.xone_Tariff_Header_Id IS null THEN l.tariff_Header_Id END,
	-- d.usxi_Tariff_Header_Id = CASE WHEN l.pricingEntity <>'BRK' AND d.usxi_Tariff_Header_Id IS null THEN l.tariff_Header_Id END
FROM #DATA d 
JOIN #Lanes l ON d.companyCode = l.companyCode and d.customerNumber=l.customerNumber AND 
(d.o_City=l.o_City AND d.o_State=l.o_State) AND d.d_ZipCode=l.d_ZipCode AND l.classification_type='City To 5-Zip'
  WHERE l.serviceEntity=@service_entity  

--•    Level 4 - City/state to city/state
	UPDATE l SET l.processed=l.classification_type,l.KNX_Lane_Id=d.knx_LaneId
	-- SET processed='City To City',
	-- d.xone_laneId = CASE  WHEN l.pricingEntity='BRK' AND d.xone_laneId IS null THEN l.USX_Lane_Id END,
	-- d.usxi_laneId = CASE WHEN l.pricingEntity <>'BRK' AND d.usxi_laneId IS null THEN l.USX_Lane_Id END,
	-- d.xone_Tariff_Header_Id = CASE  WHEN l.pricingEntity='BRK' AND d.xone_Tariff_Header_Id IS null THEN l.tariff_Header_Id END,
	-- d.usxi_Tariff_Header_Id = CASE WHEN l.pricingEntity <>'BRK' AND d.usxi_Tariff_Header_Id IS null THEN l.tariff_Header_Id END
FROM #DATA d 
  JOIN #Lanes l ON d.companyCode = l.companyCode and d.customerNumber=l.customerNumber AND 
(d.o_City =l.o_City AND d.o_State=l.o_State) AND (d.d_City=l.d_City AND d.d_State=l.d_State) 
  AND l.classification_type='City To City' 
  WHERE l.serviceEntity=@service_entity  

 --•    Level 5 - Zip to zone
	UPDATE l SET l.processed=l.classification_type,l.KNX_Lane_Id=d.knx_LaneId
	-- SET processed = '5-Zip To 3-Zip',
	-- d.xone_laneId = CASE  WHEN l.pricingEntity='BRK' AND d.xone_laneId IS null THEN l.USX_Lane_Id END,
	-- d.usxi_laneId = CASE WHEN l.pricingEntity <>'BRK' AND d.usxi_laneId IS null THEN l.USX_Lane_Id END,
	-- d.xone_Tariff_Header_Id = CASE  WHEN l.pricingEntity='BRK' AND d.xone_Tariff_Header_Id IS null THEN l.tariff_Header_Id END,
	-- d.usxi_Tariff_Header_Id = CASE WHEN l.pricingEntity <>'BRK' AND d.usxi_Tariff_Header_Id IS null THEN l.tariff_Header_Id END
  FROM #DATA d 
  JOIN #Lanes l ON d.companyCode = l.companyCode and d.customerNumber=l.customerNumber AND 
d.o_ZipCode =l.o_ZipCode AND d.d_ZipCode=l.d_ZipCode AND l.classification_type='5-Zip To 3-Zip' 
    WHERE l.serviceEntity=@service_entity  

--•    Level 6 - Zone to zip
	UPDATE l SET l.processed=l.classification_type,l.KNX_Lane_Id=d.knx_LaneId
	-- SET processed='3-Zip To 5-Zip',
	-- d.xone_laneId = CASE  WHEN l.pricingEntity='BRK' AND d.xone_laneId IS null THEN l.USX_Lane_Id END,
	-- d.usxi_laneId = CASE WHEN l.pricingEntity <>'BRK' AND d.usxi_laneId IS null THEN l.USX_Lane_Id END,
	-- d.xone_Tariff_Header_Id = CASE  WHEN l.pricingEntity='BRK' AND d.xone_Tariff_Header_Id IS null THEN l.tariff_Header_Id END,
	-- d.usxi_Tariff_Header_Id = CASE WHEN l.pricingEntity <>'BRK' AND d.usxi_Tariff_Header_Id IS null THEN l.tariff_Header_Id END
  FROM #DATA d 
  JOIN #Lanes l ON d.companyCode = l.companyCode and d.customerNumber=l.customerNumber AND 
d.o_ZipCode =l.o_ZipCode AND d.d_ZipCode=l.d_ZipCode AND l.classification_type='3-Zip To 5-Zip' 
    WHERE l.serviceEntity=@service_entity  

--•    Level 7 - City/state to zone
	UPDATE l SET l.processed=l.classification_type,l.KNX_Lane_Id=d.knx_LaneId
	-- SET processed='CityState-Zone',
	-- d.xone_laneId = CASE  WHEN l.pricingEntity='BRK' AND d.xone_laneId IS null THEN l.USX_Lane_Id END,
	-- d.usxi_laneId = CASE WHEN l.pricingEntity <>'BRK' AND d.usxi_laneId IS null THEN l.USX_Lane_Id END,
	-- d.xone_Tariff_Header_Id = CASE  WHEN l.pricingEntity='BRK' AND d.xone_Tariff_Header_Id IS null THEN l.tariff_Header_Id END,
	-- d.usxi_Tariff_Header_Id = CASE WHEN l.pricingEntity <>'BRK' AND d.usxi_Tariff_Header_Id IS null THEN l.tariff_Header_Id END
  FROM #DATA d 
  JOIN #Lanes l ON d.companyCode = l.companyCode and d.customerNumber=l.customerNumber AND 
(d.o_City=l.o_City AND d.o_State=l.o_State) AND d.d_ZipCode = l.d_ZipCode AND l.classification_type='City To 3-Zip' 
    WHERE l.serviceEntity=@service_entity  

 --•    Level 8 - Zone to city/state
	UPDATE l SET l.processed=l.classification_type,l.KNX_Lane_Id=d.knx_LaneId
	-- SET processed='3-Zip To City',
	-- d.xone_laneId = CASE  WHEN l.pricingEntity='BRK' AND d.xone_laneId IS null THEN l.USX_Lane_Id END,
	-- d.usxi_laneId = CASE WHEN l.pricingEntity <>'BRK' AND d.usxi_laneId IS null THEN l.USX_Lane_Id END,
	-- d.xone_Tariff_Header_Id = CASE  WHEN l.pricingEntity='BRK' AND d.xone_Tariff_Header_Id IS null THEN l.tariff_Header_Id END,
	-- d.usxi_Tariff_Header_Id = CASE WHEN l.pricingEntity <>'BRK' AND d.usxi_Tariff_Header_Id IS null THEN l.tariff_Header_Id END
  FROM #DATA d  
  JOIN #Lanes l ON d.companyCode = l.companyCode and d.customerNumber=l.customerNumber AND 
d.o_ZipCode =l.o_ZipCode AND (d.d_City = l.d_City and d.d_State=l.d_State) AND l.classification_type='3-Zip To City' 
    WHERE l.serviceEntity=@service_entity  

--•    Level 9 - Zone to zone
	UPDATE l SET l.processed=l.classification_type,l.KNX_Lane_Id=d.knx_LaneId
	-- SET processed='3-Zip To 3-Zip',
	-- d.xone_laneId = CASE  WHEN l.pricingEntity='BRK' AND d.xone_laneId IS null THEN l.USX_Lane_Id END,
	-- d.usxi_laneId = CASE WHEN l.pricingEntity <>'BRK' AND d.usxi_laneId IS null THEN l.USX_Lane_Id END,
	-- d.xone_Tariff_Header_Id = CASE  WHEN l.pricingEntity='BRK' AND d.xone_Tariff_Header_Id IS null THEN l.tariff_Header_Id END,
	-- d.usxi_Tariff_Header_Id = CASE WHEN l.pricingEntity <>'BRK' AND d.usxi_Tariff_Header_Id IS null THEN l.tariff_Header_Id END
  FROM #DATA d  
  JOIN #Lanes l ON d.companyCode = l.companyCode and d.customerNumber=l.customerNumber AND 
d.o_ZipCode =l.o_ZipCode AND d.d_ZipCode=l.d_ZipCode AND l.classification_type='3-Zip To 3-Zip'
    WHERE l.serviceEntity=@service_entity  

--•    Level 10 - Zip to state
	UPDATE l SET l.processed=l.classification_type,l.KNX_Lane_Id=d.knx_LaneId
	-- SET processed='5-Zip To State',
	-- d.xone_laneId = CASE  WHEN l.pricingEntity='BRK' AND d.xone_laneId IS null THEN l.USX_Lane_Id END,
	-- d.usxi_laneId = CASE WHEN l.pricingEntity <>'BRK' AND d.usxi_laneId IS null THEN l.USX_Lane_Id END,
	-- d.xone_Tariff_Header_Id = CASE  WHEN l.pricingEntity='BRK' AND d.xone_Tariff_Header_Id IS null THEN l.tariff_Header_Id END,
	-- d.usxi_Tariff_Header_Id = CASE WHEN l.pricingEntity <>'BRK' AND d.usxi_Tariff_Header_Id IS null THEN l.tariff_Header_Id END
  FROM #DATA d  
  JOIN #Lanes l ON d.companyCode = l.companyCode and d.customerNumber=l.customerNumber AND 
d.o_ZipCode=l.o_ZipCode AND d.d_State = l.d_State AND l.classification_type='5-Zip To State' 
    WHERE l.serviceEntity=@service_entity  

--•    Level 11- State to zip
	UPDATE l SET l.processed=l.classification_type,l.KNX_Lane_Id=d.knx_LaneId
	-- SET processed='State To 5-Zip',
	-- d.xone_laneId = CASE  WHEN l.pricingEntity='BRK' AND d.xone_laneId IS null THEN l.USX_Lane_Id END,
	-- d.usxi_laneId = CASE WHEN l.pricingEntity <>'BRK' AND d.usxi_laneId IS null THEN l.USX_Lane_Id END,
	-- d.xone_Tariff_Header_Id = CASE  WHEN l.pricingEntity='BRK' AND d.xone_Tariff_Header_Id IS null THEN l.tariff_Header_Id END,
	-- d.usxi_Tariff_Header_Id = CASE WHEN l.pricingEntity <>'BRK' AND d.usxi_Tariff_Header_Id IS null THEN l.tariff_Header_Id END
  FROM #DATA d 
  JOIN #Lanes l ON d.companyCode = l.companyCode and d.customerNumber=l.customerNumber AND 
d.o_State=l.o_State AND d.d_ZipCode=l.d_ZipCode AND l.classification_type='State To 5-Zip' 
    WHERE l.serviceEntity=@service_entity  

  --•    Level 12 - City/state to state
	UPDATE l SET l.processed=l.classification_type,l.KNX_Lane_Id=d.knx_LaneId
	-- SET processed='City To State',
	-- d.xone_laneId = CASE  WHEN l.pricingEntity='BRK' AND d.xone_laneId IS null THEN l.USX_Lane_Id END,
	-- d.usxi_laneId = CASE WHEN l.pricingEntity <>'BRK' AND d.usxi_laneId IS null THEN l.USX_Lane_Id END,
	-- d.xone_Tariff_Header_Id = CASE  WHEN l.pricingEntity='BRK' AND d.xone_Tariff_Header_Id IS null THEN l.tariff_Header_Id END,
	-- d.usxi_Tariff_Header_Id = CASE WHEN l.pricingEntity <>'BRK' AND d.usxi_Tariff_Header_Id IS null THEN l.tariff_Header_Id END
  FROM #DATA d 
  JOIN #Lanes l ON d.companyCode = l.companyCode and d.customerNumber=l.customerNumber AND 
(d.o_City=l.o_City AND d.o_State=l.o_State) AND d.d_State = l.d_State AND l.classification_type='City To State' 
    WHERE l.serviceEntity=@service_entity  

  --•    Level 13 - State to city/State
	UPDATE l SET l.processed=l.classification_type,l.KNX_Lane_Id=d.knx_LaneId
	-- SET processed='State To City',
	-- d.xone_laneId = CASE  WHEN l.pricingEntity='BRK' AND d.xone_laneId IS null THEN l.USX_Lane_Id END,
	-- d.usxi_laneId = CASE WHEN l.pricingEntity <>'BRK' AND d.usxi_laneId IS null THEN l.USX_Lane_Id END,
	-- d.xone_Tariff_Header_Id = CASE  WHEN l.pricingEntity='BRK' AND d.xone_Tariff_Header_Id IS null THEN l.tariff_Header_Id END,
	-- d.usxi_Tariff_Header_Id = CASE WHEN l.pricingEntity <>'BRK' AND d.usxi_Tariff_Header_Id IS null THEN l.tariff_Header_Id END
  FROM #DATA d 
  JOIN #Lanes l ON d.companyCode = l.companyCode and d.customerNumber=l.customerNumber AND 
d.o_State=l.o_State AND (d.d_City=l.d_City AND d.d_State=l.d_State) AND l.classification_type='State To City' 
    WHERE l.serviceEntity=@service_entity  



  --•    Level 14 - Zone to state
	UPDATE l SET l.processed=l.classification_type,l.KNX_Lane_Id=d.knx_LaneId
	-- SET processed='3-Zip To State',
	-- d.xone_laneId = CASE  WHEN l.pricingEntity='BRK' AND d.xone_laneId IS null THEN l.USX_Lane_Id END,
	-- d.usxi_laneId = CASE WHEN l.pricingEntity <>'BRK' AND d.usxi_laneId IS null THEN l.USX_Lane_Id END,
	-- d.xone_Tariff_Header_Id = CASE  WHEN l.pricingEntity='BRK' AND d.xone_Tariff_Header_Id IS null THEN l.tariff_Header_Id END,
	-- d.usxi_Tariff_Header_Id = CASE WHEN l.pricingEntity <>'BRK' AND d.usxi_Tariff_Header_Id IS null THEN l.tariff_Header_Id END
  FROM #DATA d 
  JOIN #Lanes l ON d.companyCode = l.companyCode and d.customerNumber=l.customerNumber AND 
d.o_ZipCode = l.o_ZipCode AND d.d_State=l.d_State AND l.classification_type='3-Zip To State' 
    WHERE l.serviceEntity=@service_entity  

  --•    Level 15 - State to zone
	UPDATE l SET l.processed=l.classification_type,l.KNX_Lane_Id=d.knx_LaneId
	-- SET processed='State To 3-Zip',
	-- d.xone_laneId = CASE  WHEN l.pricingEntity='BRK' AND d.xone_laneId IS null THEN l.USX_Lane_Id END,
	-- d.usxi_laneId = CASE WHEN l.pricingEntity <>'BRK' AND d.usxi_laneId IS null THEN l.USX_Lane_Id END,
	-- d.xone_Tariff_Header_Id = CASE  WHEN l.pricingEntity='BRK' AND d.xone_Tariff_Header_Id IS null THEN l.tariff_Header_Id END,
	-- d.usxi_Tariff_Header_Id = CASE WHEN l.pricingEntity <>'BRK' AND d.usxi_Tariff_Header_Id IS null THEN l.tariff_Header_Id END
  FROM #DATA d 
  JOIN #Lanes l ON d.companyCode = l.companyCode and d.customerNumber=l.customerNumber AND 
d.o_State=l.o_State AND d.d_ZipCode = l.d_ZipCode AND l.classification_type='State To 3-Zip' 
    WHERE  l.serviceEntity=@service_entity  

--•    Level 16 -  State to state
	UPDATE l SET l.processed=l.classification_type,l.KNX_Lane_Id=d.knx_LaneId
	-- SET processed='State To State',
	-- d.xone_laneId = CASE  WHEN l.pricingEntity='BRK' AND d.xone_laneId IS null THEN l.USX_Lane_Id END,
	-- d.usxi_laneId = CASE WHEN l.pricingEntity <>'BRK' AND d.usxi_laneId IS null THEN l.USX_Lane_Id END,
	-- d.xone_Tariff_Header_Id = CASE  WHEN l.pricingEntity='BRK' AND d.xone_Tariff_Header_Id IS null THEN l.tariff_Header_Id END,
	-- d.usxi_Tariff_Header_Id = CASE WHEN l.pricingEntity <>'BRK' AND d.usxi_Tariff_Header_Id IS null THEN l.tariff_Header_Id END
  FROM #DATA d 
JOIN #Lanes l ON d.companyCode = l.companyCode and d.customerNumber=l.customerNumber AND 
d.o_State=l.o_State  AND d.d_State=l.d_State AND l.classification_type='State To State'  
	where l.serviceEntity=@service_entity  


/* 	-------------- New	-------------- */
SELECT DISTINCT l.processed,l.companyCode,l.customerNumber,l.tariff_Header_Id,l.USX_Lane_Id,KNX_Lane_Id
FROM #Lanes l
where l.processed is not NULL
order by KNX_Lane_Id;

/************************************************
--[8/18 10:37 AM] Frankie Clement

SELECT th.tariff_header_Id,tl.tariff_lane_id,tl.lane_id,tl.lane_effective_date,tl.lane_expiration_date
FROM dbo.tariff_header AS th
    JOIN dbo.tariff_lane AS tl
        ON tl.tariff_header_Id = th.tariff_header_Id
WHERE th.customer_bill_to_id = 1045641
      AND tl.ct_from_city = 'Dallas'
      AND tl.ct_to_city = 'CONWAY'
      --AND (tl.lane_effective_date<='2023-02-18' AND tl.lane_expiration_date>='2023-08-18') OR (tl.lane_expiration_date>='2023-08-18')
      AND
      (
          ('2023-02-18' BETWEEN tl.lane_effective_date AND tl.lane_expiration_date )
          OR (tl.lane_expiration_date >= '2023-08-18')
      );

--[8/18 10:40 AM] Frankie Clement

SELECT th.tariff_header_Id,
       tl.tariff_lane_id,
       tl.lane_id
	   ,tl.lane_effective_date,tl.lane_expiration_date
FROM dbo.tariff_header AS th
    JOIN dbo.tariff_lane AS tl
        ON tl.tariff_header_Id = th.tariff_header_Id
WHERE th.customer_bill_to_id = 1045641
      AND tl.ct_from_city = 'Dallas'
      AND tl.ct_to_city = 'CONWAY'

      --AND (tl.lane_effective_date<='2023-02-18' AND tl.lane_expiration_date>='2023-08-18') OR (tl.lane_expiration_date>='2023-08-18')

      AND
      (
          (
			'2023-02-18' BETWEEN tl.lane_effective_date AND tl.lane_expiration_date )
			OR (tl.lane_expiration_date >= '2023-08-18')
			OR (tl.lane_effective_date  BETWEEN '2023-02-18' AND '2023-08-18'
          )
      );
*/


END
GO
