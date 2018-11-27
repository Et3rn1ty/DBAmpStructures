--Drop the existing table in the migration_transaction db
DROP TABLE migration_transaction.dbo.Account_Load

--Refresh any related tables
USE [SALESFORCE_DEV]
EXEC SF_Refresh 'SALESFORCE_DEV','Account','Yes'

--Select into migration_transaction from migration_source
SELECT
Cast('' as nchar(18)) as [ID]
, Cast('' as nvarchar(255)) as Error
, a.sourceAccountName as Name
, a.sourceAccountID as Migration_External_ID__c
, b.Id as ParentId

INTO migration_transaction.dbo.Account_Load
FROM migration_source.dbo.sourceAccount a

--Joins for related data already in Salesforce
left join SALESFORCE_DEV.dbo.Account b on a.sourceAccountID = b.Migration_External_ID__c

--Insert/Update/Upsert statement
USE [migration_transaction]
EXEC SF_Bulkops 'Upsert:bulkapi,batchsize(10000)','SALESFORCE_DEV','Account_Load','Migration_External_ID__c'

--Refresh the local data with everything that was loaded
USE [SALESFORCE_DEV]
EXEC SF_Refresh 'SALESFORCE_DEV','Account'