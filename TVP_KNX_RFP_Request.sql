CREATE TYPE [dbo].[KNX_RFP_Request] AS TABLE(
	[traceID] [varchar](max) NULL,
	[laneId] [int] NOT NULL,
	[companyCode] [varchar](4) NOT NULL,
	[customerNumber] [decimal](7, 0) NOT NULL,
	[originCity] [varchar](100) NULL,
	[originState] [char](2) NULL,
	[originZip] [varchar](100) NULL,
	[originMisc] [varchar](100) NULL,
	[destinationCity] [varchar](100) NULL,
	[destinationState] [char](2) NULL,
	[destinationZip] [varchar](100) NULL,
	[destinationMisc] [varchar](100) NULL,
	[equipmentType] [char](1) NULL,
	[customerMiles] [int] NULL
)
GO
