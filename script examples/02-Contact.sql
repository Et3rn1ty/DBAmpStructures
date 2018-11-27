--Drop the existing table in the migration_transaction db
DROP TABLE migration_transaction.dbo.Contact_Load

--Refresh any related tables
USE [SALESFORCE_DEV]
EXEC SF_Refresh 'SALESFORCE_DEV','Account','Yes'

--Select into migration_transaction from migration_source
SELECT
--This is our SF ID field which gets populated when insert/upsert is done, for update we need this populated ahead of time
Cast('' as nchar(18)) as [ID]
--This is the error field which gets populated when using SF_Bulkops, for SF_TableLoad this would be created in your _Result table
, Cast('' as nvarchar(255)) as Error
, a.sourceContactName as Name
, a.sourceContactEmail as Email
, a.sourceContactPhone as Phone
--It's always good to include the external ID for migration, but when upserting, the migration external id is required
, a.sourceContactID as Migration_External_ID__c
--This is how we're linking our inserted contacts to accounts via the join below
, b.Id as AccountId

--We're inserting this into our transaction table so our source tables remain static.
--	Our transaction is ephermeral as we're always dropping it before running the scripts
INTO migration_transaction.dbo.Contact_Load
FROM migration_source.dbo.sourceContact a

--Join on existing data relationships in your source data for related data already in Salesforce
--	if you don't have existing relationships in your data you may need to create combinations of data as your migration IDs to make joining possible.
left join SALESFORCE_DEV.dbo.Account b on a.sourceContactAccountID = b.Migration_External_ID__c

--Insert/Update/Upsert statement
USE [migration_transaction]
EXEC SF_Bulkops 'Upsert:bulkapi,batchsize(10000)','SALESFORCE_DEV','Account_Load','Migration_External_ID__c'

--Refresh the local data with everything that was loaded
USE [SALESFORCE_DEV]
EXEC SF_Refresh 'SALESFORCE_DEV','Account'