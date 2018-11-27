# DBAmp Structures
------
A repository for my DBAmp setup documentation and usage. This is meant as a supplemental resource for the [Official Documentation](http://forceamp.com/hats/DBAmpDoc.pdf). For installation and initial setup refer to the official documentation. This guide assumes a background in T-SQL and general familiarity with data modeling in both SQL and Salesforce.

# Index

- [Database Setup](#Database-Setup)
    - [Naming Conventions](#naming-conventions)
    - [Source Database Tips](#source-database-tips)
- [Scheduling Replication and On Demand Replication](#Scheduling-Replication-and-On-Demand-Replication)
- [API Call Management](#api-call-management)
- [Post Migration Reporting and Analysis](#post-migration-reporting-and-analysis)
- [Example Scripts](#example-scripts)

# Database Setup
Follow the official documentation for the installation and linking of your Salesforce orgs. When linking your Salesforce org follow the naming conventions outlined in the Naming Conventions sub-section. 

Generally you will want to have a database structure like this:

| Database | Contents |
| ------ | ------ |
| migration_source | All of the source tables from the original data source you're migrating |
| migration_transaction | An ephermeral transaction database from where you are loading into Salesforce  |
| orgname_prod | Your Production Salesforce org replicated tables |
| orgname_envname | N databases for each environment you're executing a migration in |

### Naming Conventions

Follow these naming conventions to make scripting and migration easier to follow:

- Prepend migration_ to any database being used for actual migration activities or storing data that is being migrated
- For each Salesforce org being linked use the org name or project name followed by `_` and the environment name 
    - Example: `MYDEVORG_DEV`, `MYDEVORG_PROD`
- Any table used to perform an action within Salesforce *MUST* be named with the Salesforce object name
    - Example: `Account` or `My_Custom_Object__c`
- For migration_transaction all tables created should have `_ACTION` appended to them. For instance, when loading new data into account the tablename should be `Account_Load` or when deleting data from Contacts the table name should be `Contact_Delete`
    - DBAmp allows you to append a single `_` statement after the tablename when transacting with Salesforce
- Within Salesforce it's best to keep a record of migrated data and important to insure migrated data can be manipulated or integrated. To do this you need to create an External ID in Salesforce *specifically* for Migration purposes (DO NOT overlap with an integration external ID as this almost always causes problems). To make it easier, create the same field on every object being migrated: `Migration_External_ID__c`
 
### Source Database Tips

Your migration_source database will contain all of the source data to be migrated into Salesforce. As with most migrations this data could be updated or have additional data included in it beyond the initial creation of this database. For that reason, it is important to have a repeatable process for creating and loading data into your migration_source. 

### Source - integration

You may need to integrate a source system directly to your migration database to insure that all updates made to the source system are added to your migration_source database automatically

- Choose an integration tool (Talend is a free opensource tool which works for this purpose)
- Create the necessary connections to your source system
- Map the source tables to your migration_source tables and insure that you're updating/appending as new data is added
- Schedule your integration to run continuously as needed
- Be sure to handle as much data transformation in your migration_source integration as possible to reduce the complexity of the migration scripts used later
- Try to keep the migration_source data model close to the source data model (with the exception of data type transformations which may be necessary to match SFDC data types) as the conversion to the Salesforce data model will be done with the migration scripts

### Source - files/db dump

Migrating from existing files or database tables is similar to integrating with the source except your 'integration' will only be run on demand as needed

- Choose an integration tool (Talend is a free opensource tool which works for this purpose)
- Create the connections to the source files or db tables
- Map the source tables to your migration_source tables (here you may want to update/append or drop and recreate depending on the possibility for changes in the source)
- Be sure to handle as much data transformation in your migration_source integration as possible to reduce the complexity of the migration scripts used later
- Try to keep the migration_source data model close to the source data model (with the exception of data type transformations which may be necessary to match SFDC data types) as the conversion to the Salesforce data model will be done with the migration scripts

# Scheduling Replication vs. On Demand Replication

For the majority of migrations you're going to be loading relational data. In order to do this we need to be able to join our migration data to the existing data in Salesforce. DBAmp provides a number of ways to pull the Salesforce data to your local SQL database. 

- `EXEC SF_Replicate` will pull the Salesforce object structure and data, basically dropping the existing tables and recreating them with all new data. This operation is required when there are changes to your object's fields/model. 
- `EXEC SF_Refresh` will pull a delta from the last successful data pull. This will not change the tables fields or model and only updates existing records and inserts new records

As migration generally occurs with some overlap to development, you'll likely need to run replication more often. Using SQL server agent you can schedule a replication script to run daily in order to keep your local SFDC database up to date. This is generally the best way to keep SQL in sync with SFDC as replicate can take a long time in orgs with a large amount of data.

If you cannot schedule the replication, it's best to limit your on-demand replicate calls to only the objects that have incurred changes since your initial replication. For all other `SF_Refresh` is the best option to sync your local database.

# API Call Management

For large migrations it's very easy to get to a point where you may be hitting your org's max API call limits. It is important to monitor and minimize API usage as much as possible. These are some of the API impacts of different DBAmp stored procs:

| Stored Proc | API Calls |
| ------ | ------ |
| SF_Bulkops w/o bulkapi | 1 call per batch of 200 records (or X records < 200 set in batchsize parameter) |
| SF_Bulkops w/ bulkapi | 1 call per batch of 10,000 records (or X records < 10,000 set in batchsize parameter) |
| SF_TableLoader | 1 call per batch of 10,000 records (or X records < 10,000 set in :soap,batchsize parameter) |

For full migrations SF_TableLoader is going to be the best option.

# Post Migration Reporting and Analysis

Reporting and analysis are going to depend on what operation you use to load the data. If you're using `SF_TableLoad` (we'll assume you are) the results of your output are loaded into a separate table with `_Result` appended to it. For example, if you upserted Account_Load with:
`EXEC SF_TableLoad 'Upsert:IgnoreFailures(20)', 'SALESFORCE_DEV', 'Account_Load', 'Migration_External_ID__c'` 
You will find your results in the same database in the table `Account_Load_Result` assuming less than 20% of records failed to load (per the :IgnoreFailures(20) option)

In the results tables you'll find the `Error` column which can be used for migration stats reporting. For example you can get the total number of successful records loaded with:
`Select count(*) from Account_Load_Result where Error like '%Operation Successful%'`

Similarly you can use T-SQL scripts on these result tables to group errors together to find common issues among the data, output stats on % of successful records if you have a threshold to match, and others. 

# Example Scripts

You can find some example scripts in the [script examples](/script-examples) folder. Most scripts will have the following basic structure:

```sql
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
```
