CREATE TYPE [dbo].[CompanyCustomerList] AS TABLE(
	[Company] [varchar](4) NOT NULL,
	[Customer] [decimal](7, 0) NOT NULL,
	PRIMARY KEY CLUSTERED 
(
	[Company] ASC,
	[Customer] ASC
)WITH (IGNORE_DUP_KEY = OFF)
)
GO
