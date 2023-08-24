SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/*
==============================================================================================================================
 Author:		Timothy Preble
 Create date:	07/19/2023
 Description:   Query Cloud Tariff to retrieve Bill To Information.
==============================================================================================================================
 Changes: 
 mm/dd/yyyy - Full Name			- Short description of changes
 07/19/2023 - Timothy Preble	- Initial Creation.
 07/24/2023 - Timothy Preble	- Add parent
 08/07/2023 - Timothy Preble	- Add lastDate, return only the most recent updated record.
 08/24/2023 - Timothy Preble  - Remove commented out code.
                                Renamed T -> TH, L->TL
==============================================================================================================================
 Indexes: 
 DatabaseName.Schema.IndexName

==============================================================================================================================
 Example: 
  DECLARE @TVP dbo.[CompanyCustomerList]
  INSERT INTO @TVP (Company,Customer)
  VALUES ('01', 885698),('01', 1001183),('01', 1171822),('01', 1210032)
  EXEC dbo.getTariffBillToInfo_ByList @pCompanyAccountList = @TVP -- CompanyAcountList
==============================================================================================================================

ALTER PROCEDURE [dbo].[getTariffBillToInfo_ByList]
(@pCompanyAccountList dbo.[CompanyCustomerList] READONLY)
AS
*/
/**Test Object/Data*/
/*
DECLARE @pCompanyAccountList dbo.CompanyCustomerList;
INSERT INTO @pCompanyAccountList ( Company, Customer )
VALUES ( '01', 885698 ) , ( '01', 1001183 ) , ( '01', 1171822 ) , ( '01', 1210032 );
--SELECT * FROM @pCompanyCustomerList
*/

DROP TABLE IF EXISTS #BillTo;
SELECT TH.company_id
     , TH.customer_bill_to_id                                                                         AS customer_bill_to_number
     , TH.customer_bill_to_name
     , CASE
          WHEN GETDATE() BETWEEN TH.contract_effective_date AND TH.contract_expiration_date
             THEN 1
          ELSE 0
       END                                                                                           AS is_active
     , COUNT(*)                                                                                      AS active_number_lanes
     , MAX(COALESCE(TL.updated_datetime, TL.created_datetime, TH.updated_datetime, TH.created_datetime)) AS lastDate
      INTO #BillTo
      FROM dbo.tariff_header          AS TH
      LEFT OUTER JOIN dbo.tariff_lane AS TL
        ON            TH.tariff_header_Id = TL.tariff_header_Id
                      AND TL.isdeleted    = '0'
                      AND GETDATE() BETWEEN TL.lane_effective_date AND TL.lane_expiration_date
      JOIN @pCompanyAccountList       AS A
        ON TH.company_id                  = A.Company
           AND TH.customer_bill_to_id     = A.Customer
     WHERE TH.isdeleted = '0'
     GROUP BY TH.company_id
            , TH.customer_bill_to_id
            , TH.customer_bill_to_name
            , CASE
                 WHEN GETDATE() BETWEEN TH.contract_effective_date AND TH.contract_expiration_date
                    THEN 1
                 ELSE 0
              END;

WITH _results AS ( 
	SELECT ROW_NUMBER() OVER ( PARTITION BY bt.company_id
                                              , bt.customer_bill_to_number
                                       ORDER BY bt.lastDate DESC ) AS rn
             , *
              FROM #BillTo AS bt
			  )

SELECT * FROM _results WHERE _results.rn = 1;
GO
