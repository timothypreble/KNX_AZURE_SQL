SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/*
==============================================================================================================================
 Author:		Timothy Preble
 Create date:	08/09/2023
 Description:   Return tariff incumbency information based on passed in customer / Geog.
==============================================================================================================================
 Changes: 
 mm/dd/yyyy - Full Name			- Short description of changes
 08/09/2023 - Timothy Preble	- Initial Creation.
==============================================================================================================================
 Indexes: 
 DatabaseName.Schema.IndexName

==============================================================================================================================
 Example: 

==============================================================================================================================
 Notes: 
 ---- 7/13/2023 Keep Inbound Information until global Customer / Lane ID has been developed ---
JIRA: https://usxpress.atlassian.net/browse/KPS-4 
CONFLUENCE: https://usxpress.atlassian.net/wiki/spaces/EN/pages/2751266817/USX+Incumbency+Information

Questions:
equipment type		do I need this ?
equipment needs		do I need this ?

MISC zip list?
committedVolume		in tariff, where & example commitment master & [tariff_commitment]?
current6MonthOrderVolume in EDW, how to query?


WILL NEED TO GET ZONE RANGES 
Check BMD SP that hit azure
Check BMD that does the activity pull. Note: BMD Might be cacheing 6 months of data ahead of time.





Notes
SELECT *
FROM [dbo].[tariff_header] AS TH
  JOIN [dbo].[tariff_lane] AS TL ON TH.tariff_header_Id = TL.tariff_header_Id
  JOIN [dbo].[tariff_rate] AS TR ON TH.tariff_header_Id = TR.tariff_header_Id AND TL.[lane_id] = TR.[lane_id]
  LEFT OUTER JOIN [dbo].[tariff_commitment] TC ON th.tariff_header_Id = tc.tariff_header_Id AND tl.lane_id = tc.lane_id
  --AND TC.isdeleted=0 AND GETDATE() BETWEEN TC.validfrom AND tc.validto
  JOIN dbo.tariff_commitment_master TCM ON TCM.commitment_id = TL.commitment_id
  WHERE TH.tariff_header_Id = 3397
  AND TL.ct_from_city='Evadale' AND TL.ct_to_city='chattanooga'
==============================================================================================================================
*/
ALTER PROCEDURE [dbo].[getTariffIncumbency_ByList_v1] ( 
	@inbound KNX_RFP_Request READONLY
	) AS

DECLARE @contractDate DATE = GETDATE()--'2023-07-28';
DECLARE @BillTO TABLE(CompanyCode VARCHAR(4) NOT NULL, customerNumber DECIMAL(7,0) NOT NULL)
INSERT INTO @BillTo
SELECT DISTINCT companyCode,customerNumber FROM @inbound
--SELECT * FROM @BillTO;

/** Get all lanes for the customer in the inbound playload & store in #Lanes **/
DROP TABLE IF EXISTS #Lanes
CREATE TABLE [#Lanes]
(
[isActive] BIT NOT NULL, --Active =1, Historical = 0
[companyCode] VARCHAR(4) NOT NULL,
[customerNumber] DECIMAL(7,0) NOT NULL,
[equipmentType] VARCHAR(50),
[equipmentNeeds] VARCHAR(50),
[pricingEntity] VARCHAR(30),
[serviceEntity] VARCHAR(30),
[o_City] VARCHAR(25),
[o_State] VARCHAR(25),
[o_ZipCode] VARCHAR(200),
--[o_Miscellaneous] VARCHAR(200),

[d_City] VARCHAR(25),
[d_State] VARCHAR(25),
[d_ZipCode] VARCHAR(200),
--[d_Miscellaneous] VARCHAR(200),
tariff_lane_id INT NULL,
[laneId] INT NOT NULL,
[commitmentPattern] VARCHAR(200),
[committedVolume] INT,	
[annualizedCommittedVolume] INT,
[effectiveOn] DATE,
[expiresOn] DATE,
[flat] DECIMAL(18,3),
	--[flatCalculated] DECIMAL(18,3),
	--[flatRatePerMile] DECIMAL(18,3),
	[minimumFlatRate] DECIMAL(18,3),	
	[ratePerMile] DECIMAL(18,3),
    contractType VARCHAR(20),
[rateType] VARCHAR(20),
[tariffId] INT NOT NULL
);

;WITH _lanes AS (
SELECT --'ABC123' AS [bidId],
CASE WHEN @contractDate BETWEEN tl.lane_effective_date AND TL.lane_expiration_date THEN 1
ELSE 0 END  AS [isActive],

       th.company_id AS [companyCode],				--Passed In
       th.customer_bill_to_id AS [customerNumber],	--Passed In
       th.equipment_type AS [equipmentType],		--Passed In
       'VAN' AS [equipmentNeeds],					--Passed In : "53' Van,  --- ,  --- ", //comma seperated or array? --??******
       -- AS [knx_LaneId],							--//order or sequence of rows KNX [ORDER] Column	 --Passed In
       -- AS [customerMiles],						--Passed In
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
--USX

       tl.tariff_lane_id AS tariff_lane_id,						--Not sure about this since we are going to represent both OTR & BRK on the same row.  Are those Diff lane IDs?
	  tl.lane_id AS [laneId],

--USXI
	   tcm.commitment_pattern AS [commitmentPattern], --This will be use to "Anualize"
       tc.alloc_capacity_min AS [committedVolume],				--??****** Annualized Committed Volume (Pricing Entity = OTR or ANY) --tariff
       CASE TCM.commitment_pattern
			WHEN 'Annually' THEN tc.alloc_capacity_min
			WHEN 'Daily' THEN tc.alloc_capacity_min*365
			WHEN 'Monthly' THEN tc.alloc_capacity_min * 12
			WHEN 'Quarterly' THEN tc.alloc_capacity_min * 4
			WHEN 'Weekly' THEN tc.alloc_capacity_min * 52
			ELSE NULL 
	   END AS annualizedCommittedVolume, 
	   --777 AS [usxi_current6MonthOrderVolume],	--??****** last 6mo of delivered order volume on asset SBU != P /// TotalTariffOrders: ( Does this need to include Spot/Quotes or Not ? ) -----****----- EDW?
       tl.lane_effective_date AS [effectiveOn],
       tl.lane_expiration_date AS [expiresOn],
       
	   /*RATE*/
	   CASE TR.rate_type WHEN 'FR' THEN tr.flat_rate ELSE NULL END  AS [flat],						
													-- (NEW) if published, is the Linehaul using customer miles and fuel scale 
													-- /// Published Rate: if rate type is FR else null

       -- AS [flatCalculated],
	   /*
		if fr then flat_rate
		if <> FR then Greater value of minimum_charge versus rpm*customer miles
	   */

		--(NEW) calculated using customer rate, will exist for all lanes, no fuel
		--///Published rate if MI * Customer MIles (Converts RPM to Flat Rate)If FR the just Published Rate
		--///if calculation < lane min rate then the lane min rate gets charged ( $992 ).

       --777 AS [flatRatePerMile],	
	   /*
		if mi then rpm or minimum_charge/customer_miles which ever is greater.
		or if not mi then flat_rate / customer miles.
	   */
													--******ALWAYS NEEDS VALUE ******** 
													--calculated using customer rate, will exist for all lanes, no fuel 
													--/// Published Rate: Flat convert to RPM OR Min convert to RPM or RPM 
													--/// calculate from tariff, ensure we don't drop below the MIN if there is a rate

       tr.minimum_charge AS [minimumFlatRate],		
		--if published, is a min flat rate 
													--/// LaneMinRate: if per miles * rate < lane min rate then the lane min rate gets charged ( $992 ).

       tr.rpm AS [ratePerMile],						
		-- (NEW) if published, is the RPM that doesn't include fuel, but is using customer miles and fuel scale /// Published Rate (RateType - MI / FR --- FR = PublishedRate / Customer Miles )
	   TL.contract_type AS [contractType],				--Primary, backup (award type)
	   TR.rate_type AS [rateType],									--MI/FR/NA
	   /*RATE*/
	   th.tariff_header_Id AS [tariffId]  
FROM [dbo].[tariff_header] AS TH	
  JOIN [dbo].[tariff_lane] AS TL ON TH.tariff_header_Id = TL.tariff_header_Id
  JOIN [dbo].[tariff_rate] AS TR ON TH.tariff_header_Id = TR.tariff_header_Id 
	  AND TL.[lane_id] = TR.[lane_id]
	  AND tr.isdeleted=0
  JOIN @BillTO  AS b ON b.companyCode = th.company_id AND b.customerNumber =th.customer_bill_to_id
  LEFT OUTER JOIN [dbo].[tariff_commitment] TC ON th.tariff_header_Id = tc.tariff_header_Id 
	AND tl.lane_id = tc.lane_id
	AND TC.isdeleted=0 
	AND @contractDate BETWEEN TC.validfrom AND tc.validto  
  JOIN dbo.tariff_commitment_master TCM ON TCM.commitment_id = TL.commitment_id
	AND tcm.isdeleted=0
  WHERE 
		th.pricing_entity IN ('ANY','OTR','BRK')
  AND	TH.service_entity IN ('ANY', 'SOLO', 'TEAM')
  AND	TH.isdeleted=0
  --AND	DATEADD(MONTH,-5,@contractDate) BETWEEN tl.lane_effective_date AND TL.lane_expiration_date
  --AND tl.lane_effective_date>= DATEADD(MONTH,-6,@contractDate)
  --AND TL.lane_expiration_date >=DATEADD(MONTH,-6,@contractDate)
)
INSERT INTO #Lanes
(
	[isActive],

    companyCode,
    customerNumber,
    equipmentType,
    equipmentNeeds,
    pricingEntity,
    serviceEntity,
    o_City,
    o_State,
    o_ZipCode,
	--[o_Miscellaneous],
    d_City,
    d_State,
    d_ZipCode,
	--[d_Miscellaneous],
	tariff_lane_id,
    laneId,
[commitmentPattern],
[committedVolume],	
[annualizedCommittedVolume],

    effectiveOn,
    expiresOn,
    flat,
	--[flatCalculated],
	--[flatRatePerMile],
	[minimumFlatRate],	
	[ratePerMile],
    contractType,
    rateType,
    tariffId
)
SELECT _lanes.isActive,
       _lanes.companyCode,
       _lanes.customerNumber,
       _lanes.equipmentType,
       _lanes.equipmentNeeds,
       _lanes.pricingEntity,
       _lanes.serviceEntity,
       _lanes.o_City,
       _lanes.o_State,
       _lanes.o_ZipCode,
       _lanes.d_City,
       _lanes.d_State,
       _lanes.d_ZipCode,
       _lanes.tariff_lane_id,
       _lanes.laneId,
       _lanes.commitmentPattern,
       _lanes.committedVolume,
       _lanes.annualizedCommittedVolume,
       _lanes.effectiveOn,
       _lanes.expiresOn,
       _lanes.flat,
       _lanes.minimumFlatRate,
       _lanes.ratePerMile,
       _lanes.contractType,
       _lanes.rateType,
       _lanes.tariffId
FROM _lanes
GROUP BY _lanes.isActive,
       _lanes.companyCode,
       _lanes.customerNumber,
       _lanes.equipmentType,
       _lanes.equipmentNeeds,
       _lanes.pricingEntity,
       _lanes.serviceEntity,
       _lanes.o_City,
       _lanes.o_State,
       _lanes.o_ZipCode,
       _lanes.d_City,
       _lanes.d_State,
       _lanes.d_ZipCode,
       _lanes.tariff_lane_id,
       _lanes.laneId,
       _lanes.commitmentPattern,
       _lanes.committedVolume,
       _lanes.annualizedCommittedVolume,
       _lanes.effectiveOn,
       _lanes.expiresOn,
       _lanes.flat,
       _lanes.minimumFlatRate,
       _lanes.ratePerMile,
       _lanes.contractType,
       _lanes.rateType,
       _lanes.tariffId
/** Get all lanes for the customer in the inbound playload **/


/* HISTORICAL DATA FOR 6 Month Vol. 
SELECT tariffId,laneId
FROM #Lanes
WHERE '2023-03-16' <=expiresOn
--WHERE DATEADD(MONTH,-6,@contractDate)
AND isActive=0
GROUP BY
       laneId,
       tariffId
ORDER BY tariffid,laneId
--22 sec
*/



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

/* * * * Create some test data * * * */
--INSERT INTO #Lanes
--(
--    companyCode, customerNumber, equipmentType, equipmentNeeds, pricingEntity, serviceEntity,
--    o_City, o_State, o_ZipCode, d_City, d_State, d_ZipCode,
--    laneId, effectiveOn, expiresOn, flat, rateType, contractType, tariffId
--)
--SELECT companyCode,
--       customerNumber,
--       equipmentType,
--       equipmentNeeds,
--       'ANY',
--       serviceEntity,
--       o_City,
--       o_State,
--       o_ZipCode,
--       d_City,
--       d_State,
	   
--       d_ZipCode,
--       laneId,
--       effectiveOn,
--       expiresOn,
--       flat,
--       rateType,
--       l.contractType,
--       tariffId
--FROM #Lanes l WHERE d_State='MO';

--INSERT INTO #Lanes
--(
--    companyCode, customerNumber, equipmentType, equipmentNeeds, pricingEntity, serviceEntity,
--    o_City, o_State, o_ZipCode, d_City, d_State, d_ZipCode,
--    laneId, effectiveOn, expiresOn, flat, rateType, contractType, tariffId
--)
--VALUES
-- ('01', 1210032, 'ANY', NULL, 'OTR','SOLO',NULL, 'AB',NULL, NULL,'MI','498-499',76,'2023-06-19 14:25:51.8381372','9999-12-31 23:59:59.9999999','999999.999','FR', 'Annual',3463)
--,('01', 1210032, 'ANY', NULL, 'OTR','SOLO',NULL, 'AB',NULL, NULL,'MI','486-488,490-491,493-497',77,'2023-06-19 14:25:51.8381372','9999-12-31 23:59:59.9999999','999999.999','FR', 'Annual',3463)

--UPDATE l SET l.pricingEntity='OTR' FROM #Lanes l WHERE d_State = 'TN';




/* * * * Define Service & Pricing Entity * * * */
DECLARE @isBRK CHAR(3) =  (SELECT TOP(1) 'BRK' FROM #Lanes WHERE pricingEntity='BRK' AND isActive=1);
DECLARE @isOTR CHAR(3) =  (SELECT TOP(1) 'OTR' FROM #Lanes WHERE pricingEntity='OTR' AND isActive=1);
DECLARE @isANY CHAR(3) =  (SELECT TOP(1) 'ANY' FROM #Lanes WHERE pricingEntity ='ANY' AND isActive=1);

DECLARE @isSOLO CHAR(4) = (SELECT TOP(1) 'SOLO' FROM #Lanes WHERE serviceEntity='SOLO' AND isActive=1);
DECLARE	@isTEAM CHAR(4) = (SELECT TOP(1) 'TEAM' FROM #Lanes WHERE serviceEntity='TEAM' AND isActive=1);
DECLARE @isANY_SERVICE CHAR(3) = (SELECT TOP(1) 'ANY' FROM #Lanes WHERE serviceEntity='ANY' AND isActive=1);

/* * * * Return Service / Pricing Entyity * * * */
DECLARE @service_entity VARCHAR(4) = COALESCE(@isSOLO,@isANY_SERVICE,@isTEAM);
DECLARE @pricing_entity CHAR(3) = COALESCE(@isOTR,@isANY);
--SELECT @pricing_entity, @service_entity,CONCAT(@isBRK, ' ',@pricing_entity)
/*8/14/2023 8:15 Meeting. SET Service = Solo, then ANY then TEAM*/


/* * * * Update outbound data table with lane incumbency * * * */
--•    Level 1 -  Zip to zip
UPDATE d SET
 d.[processed] = 'zip-to-zip'
,d.[pricingEntity] = CONCAT(@isBRK, ' ',@pricing_entity)--l.pricingEntity 
,d.[serviceEntity] = @service_entity --l.serviceEntity 

,d.[usxi_laneId] = lOTR.laneId
, d.[usxi_committedVolume] = lotr.annualizedCommittedVolume
--[usxi_current6MonthOrderVolume] INT,
,d.[usxi_effectiveOn] = lOTR.effectiveOn
,d.[usxi_expiresOn] = lOTR.expiresOn
,[usxi_flat] = lOTR.flat
--,d.[usxi_flatCalculated] 
--[usxi_flatRatePerMile] DECIMAL(18,3),
, d.[usxi_minimumFlatRate] = lotr.minimumFlatRate
, d.[usxi_ratePerMile] = lOTR.ratePerMile
, d.[usxi_contractType] = lOTR.contractType
,d.[usxi_rateType] = lOTR.rateType
,d.[usxi_Tariff_Header_Id] = lOTR.tariffId

,d.[xone_laneId] = lBRK.laneId
,d.[xone_committedVolumne] = lBRK.annualizedCommittedVolume
--,d.[xone_current6MonthOrderVolume] INT, --Get with Chaz to get this as it's built on a cross server call to PSA.  Chaz will as in Stand-Up.
,d.[xone_effectiveOn] =lBRK.effectiveOn
,d.[xone_expiresOn]  = lBRK.expiresOn
,d.[xone_flat] = lBRK.flat
--,d.[xone_flatCalculated] 
--,d.[xone_flatRatePerMile]
,d.[xone_minimumFlatRate] = lBRK.minimumFlatRate
,d.[xone_ratePerMile] = lbrk.ratePerMile
,d.[xone_rateType] = lBRK.rateType
,d.[xone_Tariff_Header_Id] = lBRK.tariffId
--SELECT *
  FROM #DATA  d
  LEFT OUTER JOIN #Lanes lBRK ON d.o_ZipCode =lBRK.o_ZipCode AND d.d_ZipCode=lBRK.d_ZipCode AND lBRK.pricingEntity='BRK' AND lBRK.serviceEntity=@service_entity AND lbrk.isActive=1
  LEFT OUTER JOIN #Lanes lOTR ON d.o_ZipCode =lOTR.o_ZipCode AND d.d_ZipCode=lOTR.d_ZipCode AND lOTR.pricingEntity=@pricing_entity AND lOTR.serviceEntity=@service_entity AND lOTR.isActive=1
  WHERE (lBRk.companyCode is NOT NULL OR lOTR.companyCode IS NOT NULL)
  AND d.processed IS NULL

--•    Level 2 -  Zip to city/state
UPDATE d SET
 d.[processed] = 'zip-to-city'
,d.[pricingEntity] = CONCAT(@isBRK, ' ',@pricing_entity)
,d.[serviceEntity] = @service_entity 

,d.[usxi_laneId] = lOTR.laneId
, d.[usxi_committedVolume] = lotr.annualizedCommittedVolume
--[usxi_current6MonthOrderVolume] INT,
,d.[usxi_effectiveOn] = lOTR.effectiveOn
,d.[usxi_expiresOn] = lOTR.expiresOn
,[usxi_flat] = lOTR.flat
, d.[usxi_minimumFlatRate] = lotr.minimumFlatRate
, d.[usxi_ratePerMile] = lOTR.ratePerMile
, d.[usxi_contractType] = lOTR.contractType
,d.[usxi_rateType] = lOTR.rateType
,d.[usxi_Tariff_Header_Id] = lOTR.tariffId

,d.[xone_laneId] = lBRK.laneId
,d.[xone_committedVolumne] = lBRK.annualizedCommittedVolume
--,d.[xone_current6MonthOrderVolume] INT, --Get with Chaz to get this as it's built on a cross server call to PSA.  Chaz will as in Stand-Up.
,d.[xone_effectiveOn] =lBRK.effectiveOn
,d.[xone_expiresOn]  = lBRK.expiresOn
,d.[xone_flat] = lBRK.flat
--,d.[xone_flatCalculated] 
--,d.[xone_flatRatePerMile]
,d.[xone_minimumFlatRate] = lBRK.minimumFlatRate
,d.[xone_ratePerMile] = lbrk.ratePerMile
,d.[xone_rateType] = lBRK.rateType
,d.[xone_Tariff_Header_Id] = lBRK.tariffId
      --SELECT *
  FROM #DATA d 
  LEFT OUTER JOIN #Lanes lBRK ON d.o_ZipCode =lBRK.o_ZipCode AND (d.d_City = lBRK.d_City AND d.d_State=lBRK.d_State) AND lBRK.pricingEntity='BRK' AND lBRK.serviceEntity=@service_entity AND lbrk.isActive=1
  LEFT OUTER JOIN #Lanes lOTR ON d.o_ZipCode =lOTR.o_ZipCode AND (d.d_City = lOTR.d_City and d.d_State=lOTR.d_State) AND lOTR.pricingEntity=@pricing_entity AND lOTR.serviceEntity=@service_entity AND lOTR.isActive=1
  WHERE (lBRk.companyCode is NOT NULL OR lOTR.companyCode IS NOT NULL)
  AND d.processed IS NULL

--•    Level 3 - City/state to zip
UPDATE d SET
 d.[processed] = 'city-to-zip'
,d.[pricingEntity] = CONCAT(@isBRK, ' ',@pricing_entity)
,d.[serviceEntity] = @service_entity 

,d.[usxi_laneId] = lOTR.laneId
, d.[usxi_committedVolume] = lotr.annualizedCommittedVolume
--[usxi_current6MonthOrderVolume] INT,
,d.[usxi_effectiveOn] = lOTR.effectiveOn
,d.[usxi_expiresOn] = lOTR.expiresOn
,[usxi_flat] = lOTR.flat
, d.[usxi_minimumFlatRate] = lotr.minimumFlatRate
, d.[usxi_ratePerMile] = lOTR.ratePerMile
, d.[usxi_contractType] = lOTR.contractType
,d.[usxi_rateType] = lOTR.rateType
,d.[usxi_Tariff_Header_Id] = lOTR.tariffId

,d.[xone_laneId] = lBRK.laneId
,d.[xone_committedVolumne] = lBRK.annualizedCommittedVolume
--,d.[xone_current6MonthOrderVolume] INT, --Get with Chaz to get this as it's built on a cross server call to PSA.  Chaz will as in Stand-Up.
,d.[xone_effectiveOn] =lBRK.effectiveOn
,d.[xone_expiresOn]  = lBRK.expiresOn
,d.[xone_flat] = lBRK.flat
--,d.[xone_flatCalculated] 
--,d.[xone_flatRatePerMile]
,d.[xone_minimumFlatRate] = lBRK.minimumFlatRate
,d.[xone_ratePerMile] = lbrk.ratePerMile
,d.[xone_rateType] = lBRK.rateType
,d.[xone_Tariff_Header_Id] = lBRK.tariffId
      --SELECT *
  FROM #DATA d 
  LEFT OUTER JOIN #Lanes lBRK ON (d.o_City=lBRK.o_City AND d.o_State=lBRK.o_State) AND d.d_ZipCode=lBRK.d_ZipCode AND lBRK.pricingEntity='BRK' AND lBRK.serviceEntity=@service_entity AND lbrk.isActive=1
  LEFT OUTER JOIN #Lanes lOTR ON (d.o_City=lOTR.o_City and d.o_State=lOTR.o_State) AND d.d_ZipCode=lOTR.d_ZipCode AND lOTR.pricingEntity=@pricing_entity AND lOTR.serviceEntity=@service_entity AND lOTR.isActive=1
  WHERE (lBRk.companyCode is NOT NULL OR lOTR.companyCode IS NOT NULL)
  AND d.processed IS NULL

--•    Level 4 - City/state to city/state
UPDATE d SET
 d.[processed] = 'city-to-city'
,d.[pricingEntity] = CONCAT(@isBRK, ' ',@pricing_entity)
,d.[serviceEntity] = @service_entity 

,d.[usxi_laneId] = lOTR.laneId
, d.[usxi_committedVolume] = lotr.annualizedCommittedVolume
--[usxi_current6MonthOrderVolume] INT,
,d.[usxi_effectiveOn] = lOTR.effectiveOn
,d.[usxi_expiresOn] = lOTR.expiresOn
,[usxi_flat] = lOTR.flat
, d.[usxi_minimumFlatRate] = lotr.minimumFlatRate
, d.[usxi_ratePerMile] = lOTR.ratePerMile
, d.[usxi_contractType] = lOTR.contractType
,d.[usxi_rateType] = lOTR.rateType
,d.[usxi_Tariff_Header_Id] = lOTR.tariffId

,d.[xone_laneId] = lBRK.laneId
,d.[xone_committedVolumne] = lBRK.annualizedCommittedVolume
--,d.[xone_current6MonthOrderVolume] INT, --Get with Chaz to get this as it's built on a cross server call to PSA.  Chaz will as in Stand-Up.
,d.[xone_effectiveOn] =lBRK.effectiveOn
,d.[xone_expiresOn]  = lBRK.expiresOn
,d.[xone_flat] = lBRK.flat
--,d.[xone_flatCalculated] 
--,d.[xone_flatRatePerMile]
,d.[xone_minimumFlatRate] = lBRK.minimumFlatRate
,d.[xone_ratePerMile] = lbrk.ratePerMile
,d.[xone_rateType] = lBRK.rateType
,d.[xone_Tariff_Header_Id] = lBRK.tariffId
      --SELECT *
  FROM #DATA d 
  LEFT OUTER JOIN #Lanes lBRK ON (d.o_City =lBRK.o_City AND d.o_State=lBRK.o_State) AND (d.d_City=lBRK.d_City AND d.d_State=lBRK.d_State) AND lBRK.pricingEntity='BRK' AND lBRK.serviceEntity=@service_entity AND lbrk.isActive=1
  LEFT OUTER JOIN #Lanes lOTR ON (d.o_City =lOTR.o_City AND d.o_State=lOTR.o_State) AND (d.d_City=lOTR.d_City AND d.d_State=lOTR.d_State) AND lOTR.pricingEntity=@pricing_entity AND lOTR.serviceEntity=@service_entity AND lOTR.isActive=1
    WHERE (lBRk.companyCode is NOT NULL OR lOTR.companyCode IS NOT NULL)
  AND d.processed IS NULL

--•    Level 5 - Zip to zone
UPDATE d SET
 d.[processed] = 'zip-to-zone'
,d.[pricingEntity] = CONCAT(@isBRK, ' ',@pricing_entity)
,d.[serviceEntity] = @service_entity 

,d.[usxi_laneId] = lOTR.laneId
, d.[usxi_committedVolume] = lotr.annualizedCommittedVolume
--[usxi_current6MonthOrderVolume] INT,
,d.[usxi_effectiveOn] = lOTR.effectiveOn
,d.[usxi_expiresOn] = lOTR.expiresOn
,[usxi_flat] = lOTR.flat
, d.[usxi_minimumFlatRate] = lotr.minimumFlatRate
, d.[usxi_ratePerMile] = lOTR.ratePerMile
, d.[usxi_contractType] = lOTR.contractType
,d.[usxi_rateType] = lOTR.rateType
,d.[usxi_Tariff_Header_Id] = lOTR.tariffId

,d.[xone_laneId] = lBRK.laneId
,d.[xone_committedVolumne] = lBRK.annualizedCommittedVolume
--,d.[xone_current6MonthOrderVolume] INT, --Get with Chaz to get this as it's built on a cross server call to PSA.  Chaz will as in Stand-Up.
,d.[xone_effectiveOn] =lBRK.effectiveOn
,d.[xone_expiresOn]  = lBRK.expiresOn
,d.[xone_flat] = lBRK.flat
--,d.[xone_flatCalculated] 
--,d.[xone_flatRatePerMile]
,d.[xone_minimumFlatRate] = lBRK.minimumFlatRate
,d.[xone_ratePerMile] = lbrk.ratePerMile
,d.[xone_rateType] = lBRK.rateType
,d.[xone_Tariff_Header_Id] = lBRK.tariffId
      --SELECT *
  FROM #DATA d 
  LEFT OUTER JOIN #Lanes lBRK ON d.o_ZipCode =lBRK.o_ZipCode AND LEFT(d.d_ZipCode,3)=LEFT(lBRK.d_ZipCode,3) AND lBRK.pricingEntity='BRK' AND lBRK.serviceEntity=@service_entity AND lbrk.isActive=1
  LEFT OUTER JOIN #Lanes lOTR ON d.o_ZipCode =lOTR.o_ZipCode AND LEFT(d.d_ZipCode,3)=LEFT(lOTR.d_ZipCode,3) AND lOTR.pricingEntity=@pricing_entity AND lOTR.serviceEntity=@service_entity AND lOTR.isActive=1
  WHERE (lBRk.companyCode is NOT NULL OR lOTR.companyCode IS NOT NULL)
  AND d.processed IS NULL

--•    Level 6 - Zone to zip
UPDATE d SET
 d.[processed] = 'zone-to-zip'
,d.[pricingEntity] = CONCAT(@isBRK, ' ',@pricing_entity)
,d.[serviceEntity] = @service_entity 

,d.[usxi_laneId] = lOTR.laneId
, d.[usxi_committedVolume] = lotr.annualizedCommittedVolume
--[usxi_current6MonthOrderVolume] INT,
,d.[usxi_effectiveOn] = lOTR.effectiveOn
,d.[usxi_expiresOn] = lOTR.expiresOn
,[usxi_flat] = lOTR.flat
, d.[usxi_minimumFlatRate] = lotr.minimumFlatRate
, d.[usxi_ratePerMile] = lOTR.ratePerMile
, d.[usxi_contractType] = lOTR.contractType
,d.[usxi_rateType] = lOTR.rateType
,d.[usxi_Tariff_Header_Id] = lOTR.tariffId

,d.[xone_laneId] = lBRK.laneId
,d.[xone_committedVolumne] = lBRK.annualizedCommittedVolume
--,d.[xone_current6MonthOrderVolume] INT, --Get with Chaz to get this as it's built on a cross server call to PSA.  Chaz will as in Stand-Up.
,d.[xone_effectiveOn] =lBRK.effectiveOn
,d.[xone_expiresOn]  = lBRK.expiresOn
,d.[xone_flat] = lBRK.flat
--,d.[xone_flatCalculated] 
--,d.[xone_flatRatePerMile]
,d.[xone_minimumFlatRate] = lBRK.minimumFlatRate
,d.[xone_ratePerMile] = lbrk.ratePerMile
,d.[xone_rateType] = lBRK.rateType
,d.[xone_Tariff_Header_Id] = lBRK.tariffId
      --SELECT *
  FROM #DATA d 
  LEFT OUTER JOIN #Lanes lBRK ON LEFT(d.o_ZipCode,3) =LEFT(lBRK.o_ZipCode,3) AND d.d_ZipCode=lBRK.d_ZipCode AND lBRK.pricingEntity='BRK' AND lBRK.serviceEntity=@service_entity AND lbrk.isActive=1
  LEFT OUTER JOIN #Lanes lOTR ON LEFT(d.o_ZipCode,3) =LEFT(lOTR.o_ZipCode,3) AND d.d_ZipCode=lOTR.d_ZipCode AND lOTR.pricingEntity=@pricing_entity AND lOTR.serviceEntity=@service_entity AND lOTR.isActive=1
  WHERE (lBRk.companyCode is NOT NULL OR lOTR.companyCode IS NOT NULL)
  AND d.processed IS NULL

--•    Level 7 - City/state to zone
UPDATE d SET
 d.[processed] = 'city-to-zone'
,d.[pricingEntity] = CONCAT(@isBRK, ' ',@pricing_entity)
,d.[serviceEntity] = @service_entity 

,d.[usxi_laneId] = lOTR.laneId
, d.[usxi_committedVolume] = lotr.annualizedCommittedVolume
--[usxi_current6MonthOrderVolume] INT,
,d.[usxi_effectiveOn] = lOTR.effectiveOn
,d.[usxi_expiresOn] = lOTR.expiresOn
,[usxi_flat] = lOTR.flat
, d.[usxi_minimumFlatRate] = lotr.minimumFlatRate
, d.[usxi_ratePerMile] = lOTR.ratePerMile
, d.[usxi_contractType] = lOTR.contractType
,d.[usxi_rateType] = lOTR.rateType
,d.[usxi_Tariff_Header_Id] = lOTR.tariffId

,d.[xone_laneId] = lBRK.laneId
,d.[xone_committedVolumne] = lBRK.annualizedCommittedVolume
--,d.[xone_current6MonthOrderVolume] INT, --Get with Chaz to get this as it's built on a cross server call to PSA.  Chaz will as in Stand-Up.
,d.[xone_effectiveOn] =lBRK.effectiveOn
,d.[xone_expiresOn]  = lBRK.expiresOn
,d.[xone_flat] = lBRK.flat
--,d.[xone_flatCalculated] 
--,d.[xone_flatRatePerMile]
,d.[xone_minimumFlatRate] = lBRK.minimumFlatRate
,d.[xone_ratePerMile] = lbrk.ratePerMile
,d.[xone_rateType] = lBRK.rateType
,d.[xone_Tariff_Header_Id] = lBRK.tariffId
      --SELECT *
  FROM #DATA d 
  LEFT OUTER JOIN #Lanes lBRK ON (d.o_City=lBRK.o_City AND d.o_State=lbrk.o_State) AND LEFT(d.d_ZipCode,3) = LEFT(lBRK.d_ZipCode,3) AND lBRK.pricingEntity='BRK' AND lBRK.serviceEntity=@service_entity AND lbrk.isActive=1
  LEFT OUTER JOIN #Lanes lOTR ON (d.o_City=lOTR.o_City AND d.o_State=lOTR.o_State) AND LEFT(d.d_ZipCode,3) = LEFT(lOTR.d_ZipCode,3) AND lOTR.pricingEntity=@pricing_entity AND lOTR.serviceEntity=@service_entity AND lOTR.isActive=1
    WHERE (lBRk.companyCode is NOT NULL OR lOTR.companyCode IS NOT NULL)
  AND d.processed IS NULL

--•    Level 8 - Zone to city/state
UPDATE d SET
 d.[processed] = 'zone-to-city'
,d.[pricingEntity] = CONCAT(@isBRK, ' ',@pricing_entity)
,d.[serviceEntity] = @service_entity 

,d.[usxi_laneId] = lOTR.laneId
, d.[usxi_committedVolume] = lotr.annualizedCommittedVolume
--[usxi_current6MonthOrderVolume] INT,
,d.[usxi_effectiveOn] = lOTR.effectiveOn
,d.[usxi_expiresOn] = lOTR.expiresOn
,[usxi_flat] = lOTR.flat
, d.[usxi_minimumFlatRate] = lotr.minimumFlatRate
, d.[usxi_ratePerMile] = lOTR.ratePerMile
, d.[usxi_contractType] = lOTR.contractType
,d.[usxi_rateType] = lOTR.rateType
,d.[usxi_Tariff_Header_Id] = lOTR.tariffId

,d.[xone_laneId] = lBRK.laneId
,d.[xone_committedVolumne] = lBRK.annualizedCommittedVolume
--,d.[xone_current6MonthOrderVolume] INT, --Get with Chaz to get this as it's built on a cross server call to PSA.  Chaz will as in Stand-Up.
,d.[xone_effectiveOn] =lBRK.effectiveOn
,d.[xone_expiresOn]  = lBRK.expiresOn
,d.[xone_flat] = lBRK.flat
--,d.[xone_flatCalculated] 
--,d.[xone_flatRatePerMile]
,d.[xone_minimumFlatRate] = lBRK.minimumFlatRate
,d.[xone_ratePerMile] = lbrk.ratePerMile
,d.[xone_rateType] = lBRK.rateType
,d.[xone_Tariff_Header_Id] = lBRK.tariffId
      --SELECT *
  FROM #DATA d 
  LEFT OUTER JOIN #Lanes lBRK ON LEFT(d.o_ZipCode,3) =LEFT(lBRK.o_ZipCode,3) AND (d.d_City = lBRK.o_City and d.d_State=lbrk.d_State) AND lBRK.pricingEntity='BRK' AND lBRK.serviceEntity=@service_entity AND lbrk.isActive=1
  LEFT OUTER JOIN #Lanes lOTR ON LEFT(d.o_ZipCode,3) =LEFT(lOTR.o_ZipCode,3) AND (d.d_City = lOTR.o_City AND d.d_State=lotr.d_State) AND lOTR.pricingEntity=@pricing_entity AND lOTR.serviceEntity=@service_entity AND lOTR.isActive=1
  WHERE (lBRk.companyCode is NOT NULL OR lOTR.companyCode IS NOT NULL)
  AND d.processed IS NULL

--•    Level 9 - Zone to zone
UPDATE d SET
 d.[processed] = 'zone-to-zone'
,d.[pricingEntity] = CONCAT(@isBRK, ' ',@pricing_entity)
,d.[serviceEntity] = @service_entity 

,d.[usxi_laneId] = lOTR.laneId
, d.[usxi_committedVolume] = lotr.annualizedCommittedVolume
--[usxi_current6MonthOrderVolume] INT,
,d.[usxi_effectiveOn] = lOTR.effectiveOn
,d.[usxi_expiresOn] = lOTR.expiresOn
,[usxi_flat] = lOTR.flat
--,d.[usxi_flatCalculated] = 
/*
if rateType = 'FR' 
	then [flat]
else 
	if 
if minimumFlatRate > (lotr.ratePerMile * d.customerMiles)
	then minimumFlatRate
	else ratePerMile* customerMiles
END

*/
--[usxi_flatRatePerMile] DECIMAL(18,3),


       -- AS [flatCalculated],
	   /*
		if fr then flat_rate
		if <> FR then Greater value of minimum_charge versus rpm*customer miles
	   */

		--(NEW) calculated using customer rate, will exist for all lanes, no fuel
		--///Published rate if MI * Customer MIles (Converts RPM to Flat Rate)If FR the just Published Rate
		--///if calculation < lane min rate then the lane min rate gets charged ( $992 ).

       --777 AS [flatRatePerMile],	
	   /*
		if mi then rpm or minimum_charge/customer_miles which ever is greater.
		or if not mi then flat_rate / customer miles.
	   */
													--******ALWAYS NEEDS VALUE ******** 
													--calculated using customer rate, will exist for all lanes, no fuel 
													--/// Published Rate: Flat convert to RPM OR Min convert to RPM or RPM 
													--/// calculate from tariff, ensure we don't drop below the MIN if there is a rate

, d.[usxi_minimumFlatRate] = lotr.minimumFlatRate
, d.[usxi_ratePerMile] = lOTR.ratePerMile
, d.[usxi_contractType] = lOTR.contractType
,d.[usxi_rateType] = lOTR.rateType
,d.[usxi_Tariff_Header_Id] = lOTR.tariffId

,d.[xone_laneId] = lBRK.laneId
,d.[xone_committedVolumne] = lBRK.annualizedCommittedVolume
--,d.[xone_current6MonthOrderVolume] INT, --Get with Chaz to get this as it's built on a cross server call to PSA.  Chaz will as in Stand-Up.
,d.[xone_effectiveOn] =lBRK.effectiveOn
,d.[xone_expiresOn]  = lBRK.expiresOn
,d.[xone_flat] = lBRK.flat
--,d.[xone_flatCalculated] 
--,d.[xone_flatRatePerMile]
,d.[xone_minimumFlatRate] = lBRK.minimumFlatRate
,d.[xone_ratePerMile] = lbrk.ratePerMile
,d.[xone_rateType] = lBRK.rateType
,d.[xone_Tariff_Header_Id] = lBRK.tariffId
--SELECT *
FROM #DATA d 
LEFT OUTER JOIN #Lanes lBRK ON LEFT(d.o_ZipCode,3) =LEFT(lBRK.o_ZipCode,3) AND LEFT(d.d_ZipCode,3)=LEFT(lBRK.d_ZipCode,3)  AND lBRK.pricingEntity='BRK' AND lBRK.serviceEntity=@service_entity AND lbrk.isActive=1
LEFT OUTER JOIN #Lanes lOTR ON LEFT(d.o_ZipCode,3) =LEFT(lOTR.o_ZipCode,3) AND LEFT(d.d_ZipCode,3)=LEFT(lOTR.d_ZipCode,3)  AND lOTR.pricingEntity=@pricing_entity AND lOTR.serviceEntity=@service_entity AND lOTR.isActive=1
WHERE (lBRk.companyCode is NOT NULL OR lOTR.companyCode IS NOT NULL)
AND d.processed IS NULL

--•    Level 10 - Zip to state
UPDATE d SET
 d.[processed] = 'zip-to-state'
,d.[pricingEntity] = CONCAT(@isBRK, ' ',@pricing_entity)
,d.[serviceEntity] = @service_entity 

,d.[usxi_laneId] = lOTR.laneId
, d.[usxi_committedVolume] = lotr.annualizedCommittedVolume
--[usxi_current6MonthOrderVolume] INT,
,d.[usxi_effectiveOn] = lOTR.effectiveOn
,d.[usxi_expiresOn] = lOTR.expiresOn
,[usxi_flat] = lOTR.flat
, d.[usxi_minimumFlatRate] = lotr.minimumFlatRate
, d.[usxi_ratePerMile] = lOTR.ratePerMile
, d.[usxi_contractType] = lOTR.contractType
,d.[usxi_rateType] = lOTR.rateType
,d.[usxi_Tariff_Header_Id] = lOTR.tariffId

,d.[xone_laneId] = lBRK.laneId
,d.[xone_committedVolumne] = lBRK.annualizedCommittedVolume
--,d.[xone_current6MonthOrderVolume] INT, --Get with Chaz to get this as it's built on a cross server call to PSA.  Chaz will as in Stand-Up.
,d.[xone_effectiveOn] =lBRK.effectiveOn
,d.[xone_expiresOn]  = lBRK.expiresOn
,d.[xone_flat] = lBRK.flat
--,d.[xone_flatCalculated] 
--,d.[xone_flatRatePerMile]
,d.[xone_minimumFlatRate] = lBRK.minimumFlatRate
,d.[xone_ratePerMile] = lbrk.ratePerMile
,d.[xone_rateType] = lBRK.rateType
,d.[xone_Tariff_Header_Id] = lBRK.tariffId
      --SELECT *
  FROM #DATA d
LEFT OUTER  JOIN #Lanes lBRK ON d.o_ZipCode=lBRK.o_ZipCode AND d.d_State = lBRK.d_State AND lBRK.pricingEntity='BRK' AND lBRK.serviceEntity=@service_entity AND lbrk.isActive=1
LEFT OUTER  JOIN #Lanes lOTR ON d.o_ZipCode=lOTR.o_ZipCode AND d.d_State = lOTR.d_State AND lOTR.pricingEntity=@pricing_entity AND lOTR.serviceEntity=@service_entity AND lOTR.isActive=1
WHERE (lBRk.companyCode is NOT NULL OR lOTR.companyCode IS NOT NULL)
AND d.processed IS NULL

--•    Level 11- State to zip
UPDATE d SET
 d.[processed] = 'state-to-zip'
,d.[pricingEntity] = CONCAT(@isBRK, ' ',@pricing_entity)--l.pricingEntity 
,d.[serviceEntity] = @service_entity --l.serviceEntity 

,d.[usxi_laneId] = lOTR.laneId
, d.[usxi_committedVolume] = lotr.annualizedCommittedVolume
--[usxi_current6MonthOrderVolume] INT,
,d.[usxi_effectiveOn] = lOTR.effectiveOn
,d.[usxi_expiresOn] = lOTR.expiresOn
,[usxi_flat] = lOTR.flat
--,d.[usxi_flatCalculated] 
--[usxi_flatRatePerMile] DECIMAL(18,3),
, d.[usxi_minimumFlatRate] = lotr.minimumFlatRate
, d.[usxi_ratePerMile] = lOTR.ratePerMile
, d.[usxi_contractType] = lOTR.contractType
,d.[usxi_rateType] = lOTR.rateType
,d.[usxi_Tariff_Header_Id] = lOTR.tariffId

,d.[xone_laneId] = lBRK.laneId
,d.[xone_committedVolumne] = lBRK.annualizedCommittedVolume
--,d.[xone_current6MonthOrderVolume] INT, --Get with Chaz to get this as it's built on a cross server call to PSA.  Chaz will as in Stand-Up.
,d.[xone_effectiveOn] =lBRK.effectiveOn
,d.[xone_expiresOn]  = lBRK.expiresOn
,d.[xone_flat] = lBRK.flat
--,d.[xone_flatCalculated] 
--,d.[xone_flatRatePerMile]
,d.[xone_minimumFlatRate] = lBRK.minimumFlatRate
,d.[xone_ratePerMile] = lbrk.ratePerMile
,d.[xone_rateType] = lBRK.rateType
,d.[xone_Tariff_Header_Id] = lBRK.tariffId
--SELECT *
  FROM #DATA d
  LEFT OUTER JOIN #Lanes lBRK ON d.o_State=lBRK.o_State AND d.d_ZipCode=lBRK.d_ZipCode AND lBRK.pricingEntity='BRK' AND lBRK.serviceEntity=@service_entity AND lbrk.isActive=1
  LEFT OUTER JOIN #Lanes lOTR ON d.o_State=lOTR.o_State AND d.d_ZipCode=lOTR.d_ZipCode AND lOTR.pricingEntity=@pricing_entity AND lOTR.serviceEntity=@service_entity AND lOTR.isActive=1
WHERE (lBRk.companyCode is NOT NULL OR lOTR.companyCode IS NOT NULL)
AND d.processed IS NULL

--•    Level 12 - City/state to state
UPDATE d SET
 d.[processed] = 'city-to-state'
,d.[pricingEntity] = CONCAT(@isBRK, ' ',@pricing_entity)
,d.[serviceEntity] = @service_entity 

,d.[usxi_laneId] = lOTR.laneId
, d.[usxi_committedVolume] = lotr.annualizedCommittedVolume
--[usxi_current6MonthOrderVolume] INT,
,d.[usxi_effectiveOn] = lOTR.effectiveOn
,d.[usxi_expiresOn] = lOTR.expiresOn
,[usxi_flat] = lOTR.flat
, d.[usxi_minimumFlatRate] = lotr.minimumFlatRate
, d.[usxi_ratePerMile] = lOTR.ratePerMile
, d.[usxi_contractType] = lOTR.contractType
,d.[usxi_rateType] = lOTR.rateType
,d.[usxi_Tariff_Header_Id] = lOTR.tariffId

,d.[xone_laneId] = lBRK.laneId
,d.[xone_committedVolumne] = lBRK.annualizedCommittedVolume
--,d.[xone_current6MonthOrderVolume] INT, --Get with Chaz to get this as it's built on a cross server call to PSA.  Chaz will as in Stand-Up.
,d.[xone_effectiveOn] =lBRK.effectiveOn
,d.[xone_expiresOn]  = lBRK.expiresOn
,d.[xone_flat] = lBRK.flat
--,d.[xone_flatCalculated] 
--,d.[xone_flatRatePerMile]
,d.[xone_minimumFlatRate] = lBRK.minimumFlatRate
,d.[xone_ratePerMile] = lbrk.ratePerMile
,d.[xone_rateType] = lBRK.rateType
,d.[xone_Tariff_Header_Id] = lBRK.tariffId
      --SELECT *
  FROM #DATA d
  LEFT OUTER JOIN #Lanes lBRK ON (d.o_City=lBRK.o_City AND d.o_State=lbrk.o_State) AND d.d_State = lBRK.d_State AND lBRK.pricingEntity='BRK' AND lBRK.serviceEntity=@service_entity AND lbrk.isActive=1
  LEFT OUTER JOIN #Lanes lOTR ON (d.o_City=lOTR.o_City AND d.o_State=lOTR.o_State) AND d.d_State = lOTR.d_State AND lOTR.pricingEntity=@pricing_entity AND lOTR.serviceEntity=@service_entity AND lOTR.isActive=1
WHERE (lBRk.companyCode is NOT NULL OR lOTR.companyCode IS NOT NULL)
AND d.processed IS NULL

--•    Level 13 - State to city/State
UPDATE d SET
 d.[processed] = 'state-to-city'
,d.[pricingEntity] = CONCAT(@isBRK, ' ',@pricing_entity)
,d.[serviceEntity] = @service_entity 

,d.[usxi_laneId] = lOTR.laneId
, d.[usxi_committedVolume] = lotr.annualizedCommittedVolume
--[usxi_current6MonthOrderVolume] INT,
,d.[usxi_effectiveOn] = lOTR.effectiveOn
,d.[usxi_expiresOn] = lOTR.expiresOn
,[usxi_flat] = lOTR.flat
, d.[usxi_minimumFlatRate] = lotr.minimumFlatRate
, d.[usxi_ratePerMile] = lOTR.ratePerMile
, d.[usxi_contractType] = lOTR.contractType
,d.[usxi_rateType] = lOTR.rateType
,d.[usxi_Tariff_Header_Id] = lOTR.tariffId

,d.[xone_laneId] = lBRK.laneId
,d.[xone_committedVolumne] = lBRK.annualizedCommittedVolume
--,d.[xone_current6MonthOrderVolume] INT, --Get with Chaz to get this as it's built on a cross server call to PSA.  Chaz will as in Stand-Up.
,d.[xone_effectiveOn] =lBRK.effectiveOn
,d.[xone_expiresOn]  = lBRK.expiresOn
,d.[xone_flat] = lBRK.flat
--,d.[xone_flatCalculated] 
--,d.[xone_flatRatePerMile]
,d.[xone_minimumFlatRate] = lBRK.minimumFlatRate
,d.[xone_ratePerMile] = lbrk.ratePerMile
,d.[xone_rateType] = lBRK.rateType
,d.[xone_Tariff_Header_Id] = lBRK.tariffId
      --SELECT *
  FROM #DATA d
  LEFT OUTER JOIN #Lanes lBRK ON d.o_State=lBRK.o_State AND (d.d_City=lBRK.d_City AND d.d_State=lBRK.d_State) AND lBRK.pricingEntity='BRK' AND lBRK.serviceEntity=@service_entity AND lbrk.isActive=1
  LEFT OUTER JOIN #Lanes lOTR ON d.o_State=lOTR.o_State AND (d.d_City=lOTR.d_City AND d.d_State=lotr.d_State) AND lOTR.pricingEntity=@pricing_entity AND lOTR.serviceEntity=@service_entity AND lOTR.isActive=1
WHERE (lBRk.companyCode is NOT NULL OR lOTR.companyCode IS NOT NULL)
AND d.processed IS NULL

--•    Level 14 - Zone to state
UPDATE d SET
 d.[processed] = 'zone-to-state'
,d.[pricingEntity] = CONCAT(@isBRK, ' ',@pricing_entity)
,d.[serviceEntity] = @service_entity 

,d.[usxi_laneId] = lOTR.laneId
, d.[usxi_committedVolume] = lotr.annualizedCommittedVolume
--[usxi_current6MonthOrderVolume] INT,
,d.[usxi_effectiveOn] = lOTR.effectiveOn
,d.[usxi_expiresOn] = lOTR.expiresOn
,[usxi_flat] = lOTR.flat
, d.[usxi_minimumFlatRate] = lotr.minimumFlatRate
, d.[usxi_ratePerMile] = lOTR.ratePerMile
, d.[usxi_contractType] = lOTR.contractType
,d.[usxi_rateType] = lOTR.rateType
,d.[usxi_Tariff_Header_Id] = lOTR.tariffId

,d.[xone_laneId] = lBRK.laneId
,d.[xone_committedVolumne] = lBRK.annualizedCommittedVolume
--,d.[xone_current6MonthOrderVolume] INT, --Get with Chaz to get this as it's built on a cross server call to PSA.  Chaz will as in Stand-Up.
,d.[xone_effectiveOn] =lBRK.effectiveOn
,d.[xone_expiresOn]  = lBRK.expiresOn
,d.[xone_flat] = lBRK.flat
--,d.[xone_flatCalculated] 
--,d.[xone_flatRatePerMile]
,d.[xone_minimumFlatRate] = lBRK.minimumFlatRate
,d.[xone_ratePerMile] = lbrk.ratePerMile
,d.[xone_rateType] = lBRK.rateType
,d.[xone_Tariff_Header_Id] = lBRK.tariffId
      --SELECT *
  FROM #DATA d
  LEFT OUTER JOIN #Lanes lBRK ON LEFT(d.o_ZipCode,3) = LEFT(lBRK.o_ZipCode,3) AND d.d_State=lBRK.d_State AND lBRK.pricingEntity='BRK' AND lBRK.serviceEntity=@service_entity AND lbrk.isActive=1
  LEFT OUTER JOIN #Lanes lOTR ON LEFT(d.o_ZipCode,3) = LEFT(lOTR.o_ZipCode,3) AND d.d_State=lOTR.d_State AND lOTR.pricingEntity=@pricing_entity AND lOTR.serviceEntity=@service_entity AND lOTR.isActive=1
WHERE (lBRk.companyCode is NOT NULL OR lOTR.companyCode IS NOT NULL)
AND d.processed IS NULL

--•    Level 15 - State to zone
UPDATE d SET
 d.[processed] = 'state-to-zone'
,d.[pricingEntity] = CONCAT(@isBRK, ' ',@pricing_entity)
,d.[serviceEntity] = @service_entity 

,d.[usxi_laneId] = lOTR.laneId
, d.[usxi_committedVolume] = lotr.annualizedCommittedVolume
--[usxi_current6MonthOrderVolume] INT,
,d.[usxi_effectiveOn] = lOTR.effectiveOn
,d.[usxi_expiresOn] = lOTR.expiresOn
,[usxi_flat] = lOTR.flat
, d.[usxi_minimumFlatRate] = lotr.minimumFlatRate
, d.[usxi_ratePerMile] = lOTR.ratePerMile
, d.[usxi_contractType] = lOTR.contractType
,d.[usxi_rateType] = lOTR.rateType
,d.[usxi_Tariff_Header_Id] = lOTR.tariffId

,d.[xone_laneId] = lBRK.laneId
,d.[xone_committedVolumne] = lBRK.annualizedCommittedVolume
--,d.[xone_current6MonthOrderVolume] INT, --Get with Chaz to get this as it's built on a cross server call to PSA.  Chaz will as in Stand-Up.
,d.[xone_effectiveOn] =lBRK.effectiveOn
,d.[xone_expiresOn]  = lBRK.expiresOn
,d.[xone_flat] = lBRK.flat
--,d.[xone_flatCalculated] 
--,d.[xone_flatRatePerMile]
,d.[xone_minimumFlatRate] = lBRK.minimumFlatRate
,d.[xone_ratePerMile] = lbrk.ratePerMile
,d.[xone_rateType] = lBRK.rateType
,d.[xone_Tariff_Header_Id] = lBRK.tariffId
      --SELECT *
  FROM #DATA d
  LEFT OUTER JOIN #Lanes lBRK ON d.o_State=lBRK.o_State AND LEFT(d.d_ZipCode,3) = LEFT(lBRK.d_ZipCode,3) AND lBRK.pricingEntity='BRK' AND lBRK.serviceEntity=@service_entity AND lbrk.isActive=1
  LEFT OUTER JOIN #Lanes lOTR ON d.o_State=lOTR.o_State AND LEFT(d.d_ZipCode,3) = LEFT(lOTR.d_ZipCode,3) AND lOTR.pricingEntity=@pricing_entity AND lOTR.serviceEntity=@service_entity AND lOTR.isActive=1
WHERE (lBRk.companyCode is NOT NULL OR lOTR.companyCode IS NOT NULL)
AND d.processed IS NULL

--•    Level 16 -  State to state
UPDATE d SET
 d.[processed] = 'state-to-state'
,d.[pricingEntity] = CONCAT(@isBRK, ' ',@pricing_entity)
,d.[serviceEntity] = @service_entity 

,d.[usxi_laneId] = lOTR.laneId
, d.[usxi_committedVolume] = lotr.annualizedCommittedVolume
--[usxi_current6MonthOrderVolume] INT,
,d.[usxi_effectiveOn] = lOTR.effectiveOn
,d.[usxi_expiresOn] = lOTR.expiresOn
,[usxi_flat] = lOTR.flat
, d.[usxi_minimumFlatRate] = lotr.minimumFlatRate
, d.[usxi_ratePerMile] = lOTR.ratePerMile
, d.[usxi_contractType] = lOTR.contractType
,d.[usxi_rateType] = lOTR.rateType
,d.[usxi_Tariff_Header_Id] = lOTR.tariffId

,d.[xone_laneId] = lBRK.laneId
,d.[xone_committedVolumne] = lBRK.annualizedCommittedVolume
--,d.[xone_current6MonthOrderVolume] INT, --Get with Chaz to get this as it's built on a cross server call to PSA.  Chaz will as in Stand-Up.
,d.[xone_effectiveOn] =lBRK.effectiveOn
,d.[xone_expiresOn]  = lBRK.expiresOn
,d.[xone_flat] = lBRK.flat
--,d.[xone_flatCalculated] 
--,d.[xone_flatRatePerMile]
,d.[xone_minimumFlatRate] = lBRK.minimumFlatRate
,d.[xone_ratePerMile] = lbrk.ratePerMile
,d.[xone_rateType] = lBRK.rateType
,d.[xone_Tariff_Header_Id] = lBRK.tariffId
      --SELECT *
  FROM #DATA d
  LEFT OUTER JOIN #Lanes lBRK ON d.o_State=lBRK.o_State AND d.d_State=lBRK.d_State  AND lBRK.pricingEntity='BRK' AND lBRK.serviceEntity=@service_entity AND lbrk.isActive=1
  LEFT OUTER JOIN #Lanes lOTR ON d.o_State=lOTR.o_State AND d.d_State=lOTR.d_State AND lOTR.pricingEntity=@pricing_entity AND lOTR.serviceEntity=@service_entity AND lOTR.isActive=1
WHERE (lBRk.companyCode is NOT NULL OR lOTR.companyCode IS NOT NULL)
AND d.processed IS NULL


SELECT *
FROM #DATA
WHERE processed IS NOT NULL
ORDER BY knx_LaneId;
GO
