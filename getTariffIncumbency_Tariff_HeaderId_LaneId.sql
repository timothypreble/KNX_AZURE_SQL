SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/*
==============================================================================================================================
 Author:		Timothy Preble
 Create date:	08/09/2023
 Description:   Return tariff incumbency information based on passed in Tariff Header & Lane
==============================================================================================================================
 Changes: 
 mm/dd/yyyy - Full Name			- Short description of changes
 08/31/2023 - Timothy Preble	- Initial Creation.
 
==============================================================================================================================
 Indexes: 
 DatabaseName.Schema.IndexName

==============================================================================================================================
 Example: 

==============================================================================================================================
 Notes: 
 ---- 7/13/2023 Keep Inbound Information until global Customer / Lane ID has been developed ---
JIRA: 
CONFLUENCE: 
==============================================================================================================================
 Extras:

Create Type KNX_RFP_Request_HeaderLane as TABLE  (companyCode VARCHAR(4), customerNumber DECIMAL(7,0), equipmentType CHAR(1),laneId INT, customerMiles decimal(18,3)
, [header] bigint, [lane] bigint )

==============================================================================================================================
*/
CREATE	 PROCEDURE [dbo].[getTariffIncumbency_Tariff_HeaderId_LaneId] ( @inbound KNX_RFP_Request_HeaderLane READONLY) AS

BEGIN
/* * * * TEST * * * */
	-- DECLARE @inbound KNX_RFP_Request_HeaderLane;
    -- insert into @inbound
    -- values
    -- ( '01',32510,'V',1,1,3327, 127 ),
    -- ( '01',32510,'V',2,1,3327, 130 ),
    -- ( '01',32510,'V',3,1,3327, 128 ),
    -- ( '01',32510,'V',4,1,3327, 131 ),
    -- ( '01',32510,'V',5,1,3327, 125 ),
    -- ( '01',32510,'V',6,1,3327, 126 ),
    -- ( '01',32510,'V',7,1,3327, 54 ),
    -- ( '01',32510,'V',8,1,3327, 129 )

    -- SELECT 'Inbound', * from @inbound;
/* * * * TEST * * * */

/* * * * Set Variables * * * */
DECLARE @contractDate DATE = GETDATE();
DECLARE @BillTO TABLE(CompanyCode VARCHAR(4) NOT NULL, customerNumber DECIMAL(7,0) NOT NULL);
INSERT INTO @BillTo
SELECT DISTINCT companyCode,customerNumber FROM @inbound
-- SELECT * FROM @BillTO;

/* * * * Get all tariff lanes for the customer in the inbound playload & store in #Lanes * * * */
DROP TABLE IF EXISTS #Lanes;
CREATE TABLE [#Lanes]
(
    [isActive] BIT NOT NULL, --Active =1, Historical = 0
    [companyCode] VARCHAR(4) NOT NULL,
    [customerNumber] DECIMAL(7, 0) NOT NULL,
    [equipmentType] VARCHAR(50) NULL,
    [equipmentNeeds] VARCHAR(50) NULL,
    [pricingEntity] VARCHAR(30) NULL,
    [serviceEntity] VARCHAR(30) NULL,
    [o_City] VARCHAR(25) NULL,
    [o_State] VARCHAR(25) NULL,
    [o_ZipCode] VARCHAR(200) NULL,
    --[o_Miscellaneous] VARCHAR(200) NULL,
    [d_City] VARCHAR(25) NULL,
    [d_State] VARCHAR(25) NULL,
    [d_ZipCode] VARCHAR(200) NULL,
    --[d_Miscellaneous] VARCHAR(200) NULL,
    [tariff_lane_id] INT NULL,
    [laneId] INT NOT NULL,
    [group_id] INT NULL,
    [commitmentPattern] VARCHAR(200) NULL,
    [committedVolume] INT NULL,
    [annualizedCommittedVolume] INT NULL,
    [effectiveOn] DATE NULL,
    [expiresOn] DATE NULL,
    [flat] DECIMAL(18, 3) NULL,
    --[flatCalculated] DECIMAL(18,3),
    --[flatRatePerMile] DECIMAL(18,3),
    [minimumFlatRate] DECIMAL(18, 3) NULL,
    [ratePerMile] DECIMAL(18, 3) NULL,
    contractType VARCHAR(20) NULL,
    [rateType] VARCHAR(20) NULL,
    [tariffId] INT NOT NULL,
    [tariff] VARCHAR(30) NULL,
    [tariff_item] VARCHAR(50) NULL,
    [classification_type] VARCHAR(100) NULL
);

INSERT INTO #Lanes
(
	[isActive],
    [companyCode],
    [customerNumber],
    [equipmentType],
    [equipmentNeeds],
    [pricingEntity],
    [serviceEntity],
    [o_City],
    [o_State],
    [o_ZipCode],
	--[o_Miscellaneous],
    [d_City],
    [d_State],
    [d_ZipCode],
	--[d_Miscellaneous],
	[tariff_lane_id],
    [laneId],
	[group_id],
	[commitmentPattern],
	[committedVolume],	
	[annualizedCommittedVolume],
    [effectiveOn],
    [expiresOn],
    [flat],
	--[flatCalculated],		--**Calculated by .Net Service**
	--[flatRatePerMile],	--**Calculated by .Net Service**
	[minimumFlatRate],	
	[ratePerMile],
    [contractType],
    [rateType],
    [tariffId],
	[tariff],
	[tariff_item],
	[classification_type]
    
)
SELECT --'ABC123' AS [bidId],
	CASE WHEN @contractDate BETWEEN tl.lane_effective_date AND TL.lane_expiration_date THEN 1
	ELSE 0 END  AS [isActive],

    th.company_id AS [companyCode],				--Passed In
	th.customer_bill_to_id AS [customerNumber],	--Passed In
	th.equipment_type AS [equipmentType],		--Passed In
	'VAN' AS [equipmentNeeds],					--********** REMOVE THIS **********
	-- AS [knx_LaneId],							--//order or sequence of rows KNX [ORDER] Column	 --Passed In
	-- AS [customerMiles],						--Passed In
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
--USX
    tl.tariff_lane_id AS tariff_lane_id,		
	tl.lane_id AS [laneId],
    
	tl.group_id [group_id],
	tcm.commitment_pattern AS [commitmentPattern], 
    tc.alloc_capacity_min AS [committedVolume],				
    CASE TCM.commitment_pattern
		WHEN 'Annually' THEN tc.alloc_capacity_min
		WHEN 'Daily' THEN tc.alloc_capacity_min*365
		WHEN 'Monthly' THEN tc.alloc_capacity_min * 12
		WHEN 'Quarterly' THEN tc.alloc_capacity_min * 4
		WHEN 'Weekly' THEN tc.alloc_capacity_min * 52
		ELSE NULL 
	END AS annualizedCommittedVolume, 
	-- AS [usxi_current6MonthOrderVolume],		-- Curated from SP on PSA and combined into the .Net Playfile retun.
    tl.lane_effective_date AS [effectiveOn],
    tl.lane_expiration_date AS [expiresOn],
/*RATE*/
	CASE TR.rate_type WHEN 'FR' THEN tr.flat_rate ELSE NULL END  AS [flat],						
    -- AS [flatCalculated],		-- **** Calculated by .Net ****
    -- AS [flatRatePerMile],	-- **** Calculated by .Net ****
    tr.minimum_charge AS [minimumFlatRate],
    tr.rpm AS [ratePerMile],						
	TL.contract_type AS [contractType],				--Primary, backup (award type)
	TR.rate_type AS [rateType],						--MI/FR/NA
	th.tariff_header_Id AS [tariffId],
	th.tariff,
	th.tariff_item,
	tl.classification_type
FROM [dbo].[tariff_header] AS TH	
	-- JOIN [dbo].[TARIFF_CROSS_REFERENCE] TCR ON th.customer_bill_to_id = tcr.TARIFF_CONT_BILTO_ID
		-- AND CONCAT(th.tariff,'-',TH.tariff_item) = tcr.TARIFF_CUST_BUS_UNIT
  JOIN [dbo].[tariff_lane] AS TL ON TH.tariff_header_Id = TL.tariff_header_Id AND tl.isdeleted=0
  JOIN [dbo].[tariff_rate] AS TR ON TH.tariff_header_Id = TR.tariff_header_Id AND TL.[lane_id] = TR.[lane_id] AND tr.isdeleted=0
  join @inbound i on tl.tariff_header_Id=i.header and tl.lane_id=i.lane

--   JOIN @BillTO  AS b ON b.companyCode = th.company_id 
					-- AND b.customerNumber = tcr.TARIFF_BILL_TO

  LEFT JOIN [dbo].[tariff_commitment] TC ON th.tariff_header_Id = tc.tariff_header_Id
	AND tl.lane_id = tc.lane_id
	AND TC.isdeleted=0 
	AND @contractDate BETWEEN tc.commit_effective_date AND tc.commit_expiry_date
  LEFT JOIN dbo.tariff_commitment_master TCM ON TCM.commitment_id = TL.commitment_id
	AND tcm.isdeleted=0
  WHERE 
	-- 	th.pricing_entity IN ('ANY','OTR','BRK')
	-- AND	TH.service_entity IN ('ANY', 'SOLO', 'TEAM') AND 
	TH.isdeleted=0
/* * * *  Get all tariff lanes for the customer in the inbound playload & store in #Lanes * * * */


/* * * * Update Grouped lanes with the primary lane's commitment * * * */
UPDATE l
SET l.annualizedCommittedVolume = g.annualizedCommittedVolume
FROM #Lanes l
    JOIN
    (
        SELECT DISTINCT tariffId, group_id, annualizedCommittedVolume
        FROM #Lanes
        WHERE ISNULL(group_id, 0) <> 0
              AND annualizedCommittedVolume <> 0
    ) g
        ON g.tariffId = l.tariffId AND g.group_id = l.group_id
WHERE ISNULL(l.annualizedCommittedVolume, 0) = 0;

/* * * * Create Temp outbound table * * * */
DROP TABLE IF EXISTS #Data;
CREATE TABLE [#DATA]
(   header bigint null,lane bigint null,
    processed VARCHAR(50) NULL,
    [bidId] VARCHAR(100) NULL,					-- **** REMOVE ****
    [companyCode] VARCHAR(4) NOT NULL,
    [customerNumber] INT NOT NULL,
    [equipmentType] CHAR(1),
    [knx_LaneId] INT NOT NULL,
    [customerMiles] INT,
    [pricingEntity] VARCHAR(100),
    [serviceEntity] VARCHAR(100),
-- ORIGIN
    [o_City] VARCHAR(100),
    [o_State] CHAR(2),
    [o_Zip] VARCHAR(100),
    [o_ZipCode] VARCHAR(100),
    [o_Miscellaneous] VARCHAR(100),
-- DESTINATION
    [d_City] VARCHAR(100),
    [d_State] CHAR(2),
    [d_zip] VARCHAR(100),
    [d_ZipCode] VARCHAR(100),
    [d_Miscellaneous] VARCHAR(100),
-- USXI (OTR / ANY)) --
    [usxi_laneId] VARCHAR(100),
    [usxi_committedVolume] INT,
    [usxi_effectiveOn] DATETIME,
    [usxi_expiresOn] DATETIME,
    [usxi_flat] DECIMAL(18, 3),
    [usxi_flatCalculated] DECIMAL(18, 3),
    [usxi_flatRatePerMile] DECIMAL(18, 3),
    [usxi_minimumFlatRate] DECIMAL(18, 3),
    [usxi_ratePerMile] DECIMAL(18, 3),
    [usxi_rateType] VARCHAR(100),
    [usxi_contractType] VARCHAR(100),
    [usxi_Tariff_Header_Id] INT,
-- XONE (Brokerage) --
    [xone_laneId] VARCHAR(100),
    [xone_committedVolumne] INT,
    [xone_effectiveOn] DATETIME,
    [xone_expiresOn] DATETIME,
    [xone_flat] DECIMAL(18, 3),
    [xone_flatCalculated] DECIMAL(18, 3),
    [xone_flatRatePerMile] DECIMAL(18, 3),
    [xone_minimumFlatRate] DECIMAL(18, 3),
    [xone_ratePerMile] DECIMAL(18, 3),
    [xone_rateType] VARCHAR(100),
    [xone_contractType] VARCHAR(100),
    [xone_Tariff_Header_Id] INT,
    [usxi_Tariff] VARCHAR(30),
    [usxi_Item] VARCHAR(50),
    [xone_Tariff] VARCHAR(30),
    [xone_Item] VARCHAR(50)
);

/* * * * Fill temp outbound table with INBOUND RFP DATA.  WILL MATCH AGAINST THIS * * * */
INSERT INTO #DATA
(
    header,lane,
    companyCode,
    customerNumber,
    equipmentType,
    knx_LaneId,
    -- o_City,
    -- o_State,
	-- o_Zip,
    -- o_ZipCode,
    -- o_Miscellaneous,
    -- d_City,
    -- d_State,
	-- d_zip,
    -- d_ZipCode,
    -- d_Miscellaneous,
    customerMiles
)

SELECT header,lane,
       companyCode,
       customerNumber,
       equipmentType,
	   laneId,
	--    originCity,
    --    originState,
    --    originZip,
	--    COALESCE(i.originZip,i.originMisc),
    --    originMisc,
    --    destinationCity,
    --    destinationState,
    --    destinationZip,
	--    COALESCE(i.destinationZip,i.destinationMisc),
    --    destinationMisc,
       customerMiles
FROM @inbound i;


/* * * * Define Service & Pricing Entity * * * */
DECLARE @isBRK CHAR(3) =  (SELECT TOP(1) 'BRK' FROM #Lanes WHERE pricingEntity='BRK' AND isActive=1);
DECLARE @isOTR CHAR(3) =  (SELECT TOP(1) 'OTR' FROM #Lanes WHERE pricingEntity='OTR' AND isActive=1);
DECLARE @isANY CHAR(3) =  (SELECT TOP(1) 'ANY' FROM #Lanes WHERE pricingEntity ='ANY' AND isActive=1);

DECLARE @isSOLO CHAR(4) = (SELECT TOP(1) 'SOLO' FROM #Lanes WHERE serviceEntity='SOLO' AND isActive=1);
DECLARE	@isTEAM CHAR(4) = (SELECT TOP(1) 'TEAM' FROM #Lanes WHERE serviceEntity='TEAM' AND isActive=1);
DECLARE @isANY_SERVICE CHAR(3) = (SELECT TOP(1) 'ANY' FROM #Lanes WHERE serviceEntity='ANY' AND isActive=1);

DECLARE @service_entity VARCHAR(4) = COALESCE(@isSOLO,@isANY_SERVICE,@isTEAM);
DECLARE @pricing_entity CHAR(3) = COALESCE(@isOTR,@isANY);
-- SELECT @pricing_entity, @service_entity,CONCAT(@isBRK, ' ',@pricing_entity)

/* * * * Update outbound data table with lane incumbency * * * */
UPDATE d
SET d.[processed] = 'Header_Lane',
    d.[pricingEntity] = CONCAT(@isBRK, ' ', @pricing_entity),
    d.[serviceEntity] = @service_entity,
-- GEOG
    d.o_City = COALESCE(lbrk.o_City,lOTR.o_City),
    d.o_State = COALESCE(lBRK.o_State, lOTR.o_State),
    d.o_Zip = COALESCE(lBRK.o_ZipCode, lOTR.o_ZipCode),
    d.o_ZipCode = COALESCE(lBRK.o_ZipCode, lOTR.o_ZipCode),
    d.d_City = COALESCE(lBRK.d_City, lOTR.d_City),
    d.d_State = COALESCE(lBRK.d_State, lOTR.d_State),
    d.d_zip = COALESCE(lBRK.d_ZipCode, lOTR.d_ZipCode),
    d.d_ZipCode = COALESCE(lBRK.d_ZipCode, lOTR.d_ZipCode),
-- USXI (OTR/ANY)
    d.[usxi_laneId] = lOTR.laneId,
    d.[usxi_committedVolume] = lOTR.annualizedCommittedVolume,
    d.[usxi_effectiveOn] = lOTR.effectiveOn,
    d.[usxi_expiresOn] = lOTR.expiresOn,
    d.[usxi_flat] = lOTR.flat,
    d.[usxi_minimumFlatRate] = lOTR.minimumFlatRate,
    d.[usxi_ratePerMile] = lOTR.ratePerMile,
    d.[usxi_contractType] = lOTR.contractType,
    d.[usxi_rateType] = lOTR.rateType,
    d.[usxi_Tariff_Header_Id] = lOTR.tariffId,
    --XONE (BRK)
    d.[xone_laneId] = lBRK.laneId,
    d.[xone_committedVolumne] = lBRK.annualizedCommittedVolume,
    d.[xone_effectiveOn] = lBRK.effectiveOn,
    d.[xone_expiresOn] = lBRK.expiresOn,
    d.[xone_flat] = lBRK.flat,
    d.[xone_minimumFlatRate] = lBRK.minimumFlatRate,
    d.[xone_ratePerMile] = lBRK.ratePerMile,
    d.[xone_rateType] = lBRK.rateType,
    d.[xone_Tariff_Header_Id] = lBRK.tariffId,
--Tariff
    d.[usxi_Tariff] = lOTR.tariff,
    d.[usxi_Item] = lOTR.tariff_item,
    d.[xone_Tariff] = lBRK.tariff,
    d.[xone_Item] = lBRK.tariff_item
FROM #DATA d
  LEFT OUTER JOIN #Lanes lBRK ON lBRK.tariffId = d.header and LBRK.laneId=d.lane
	AND lBRK.pricingEntity='BRK' AND lBRK.serviceEntity=@service_entity AND lbrk.isActive=1
  LEFT OUTER JOIN #Lanes lOTR ON lOTR.tariffId = d.header and lOTR.laneId=d.lane
	AND lOTR.pricingEntity=@pricing_entity AND lOTR.serviceEntity=@service_entity AND lOTR.isActive=1
  WHERE (lBRk.companyCode is NOT NULL OR lOTR.companyCode IS NOT NULL)
	AND d.processed IS NULL;



/* * * * RETURN ANY MATCHES * * * */
SELECT *
FROM #DATA
WHERE processed IS NOT null
ORDER BY knx_LaneId;

END
GO
