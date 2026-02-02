
/*
===========================================================
 SQL MONITORING TOOL – REPOSITORY INSTALL WRAPPER
 Database : SqlMonitorRepo
 Purpose  : One-click repository setup (schemas, tables,
            partitions, views)
===========================================================
*/

IF DB_NAME() <> 'SqlMonitorRepo'
BEGIN
    RAISERROR('Please run this script in SqlMonitorRepo database.',16,1);
    RETURN;
END;
GO

/* Schemas */
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'inventory')
    EXEC('CREATE SCHEMA inventory');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'metrics')
    EXEC('CREATE SCHEMA metrics');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'security')
    EXEC('CREATE SCHEMA security');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'restoreinfo')
    EXEC('CREATE SCHEMA restoreinfo');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'recommendations')
    EXEC('CREATE SCHEMA recommendations');
GO

/* Partition Function */
IF NOT EXISTS (SELECT 1 FROM sys.partition_functions WHERE name = 'pf_MonthlyDate')
BEGIN
    CREATE PARTITION FUNCTION pf_MonthlyDate (DATETIME2)
    AS RANGE RIGHT FOR VALUES (
        '2024-01-01','2024-02-01','2024-03-01','2024-04-01',
        '2024-05-01','2024-06-01','2024-07-01','2024-08-01',
        '2024-09-01','2024-10-01','2024-11-01','2024-12-01',
        '2025-01-01','2025-02-01','2025-03-01','2025-04-01',
        '2025-05-01','2025-06-01','2025-07-01','2025-08-01',
        '2025-09-01','2025-10-01','2025-11-01','2025-12-01'
    );
END;
GO

/* Partition Scheme */
IF NOT EXISTS (SELECT 1 FROM sys.partition_schemes WHERE name = 'ps_MonthlyDate')
BEGIN
    CREATE PARTITION SCHEME ps_MonthlyDate
    AS PARTITION pf_MonthlyDate
    ALL TO ([PRIMARY]);
END;
GO

/* Inventory Tables */
IF OBJECT_ID('inventory.Instances') IS NULL
CREATE TABLE inventory.Instances (
    InstanceId INT IDENTITY PRIMARY KEY,
    InstanceName SYSNAME NOT NULL,
    Environment VARCHAR(20),
    SqlVersion VARCHAR(200),
    Edition VARCHAR(100),
    OsVersion VARCHAR(200),
    LastReboot DATETIME2,
    CreatedAt DATETIME2 DEFAULT SYSDATETIME()
);
GO

IF OBJECT_ID('inventory.Databases') IS NULL
CREATE TABLE inventory.Databases (
    DatabaseId INT IDENTITY PRIMARY KEY,
    InstanceId INT NOT NULL,
    DatabaseName SYSNAME NOT NULL,
    Status VARCHAR(20),
    RecoveryModel VARCHAR(20),
    CompatibilityLevel INT,
    SizeGB DECIMAL(10,2),
    LastSeen DATETIME2,
    CONSTRAINT FK_Databases_Instance
        FOREIGN KEY (InstanceId)
        REFERENCES inventory.Instances(InstanceId)
);
GO

/* Partitioned Metrics Tables */
IF OBJECT_ID('metrics.DatabaseSessionUsage') IS NULL
BEGIN
    CREATE TABLE metrics.DatabaseSessionUsage (
        InstanceId INT NOT NULL,
        DatabaseName SYSNAME NOT NULL,
        ActiveSessionCount INT NOT NULL,
        SampleTime DATETIME2 NOT NULL
    ) ON ps_MonthlyDate (SampleTime);

    CREATE CLUSTERED INDEX CX_DatabaseSessionUsage
    ON metrics.DatabaseSessionUsage (SampleTime, InstanceId, DatabaseName)
    ON ps_MonthlyDate (SampleTime);
END;
GO

IF OBJECT_ID('metrics.CpuUsage') IS NULL
BEGIN
    CREATE TABLE metrics.CpuUsage (
        InstanceId INT NOT NULL,
        CpuPercent DECIMAL(5,2),
        SampleTime DATETIME2 NOT NULL
    ) ON ps_MonthlyDate (SampleTime);

    CREATE CLUSTERED INDEX CX_CpuUsage
    ON metrics.CpuUsage (SampleTime, InstanceId)
    ON ps_MonthlyDate (SampleTime);
END;
GO

/* Security & Restore Tables */
IF OBJECT_ID('security.OrphanedUsers') IS NULL
CREATE TABLE security.OrphanedUsers (
    InstanceId INT,
    DatabaseName SYSNAME,
    UserName SYSNAME,
    DetectedOn DATETIME2 DEFAULT SYSDATETIME()
);
GO

IF OBJECT_ID('restoreinfo.DatabaseRestoreHistory') IS NULL
CREATE TABLE restoreinfo.DatabaseRestoreHistory (
    InstanceId INT,
    DatabaseName SYSNAME,
    RestoreDate DATETIME2,
    SourceDatabase SYSNAME,
    BackupFile NVARCHAR(4000),
    CollectedOn DATETIME2 DEFAULT SYSDATETIME()
);
GO

/* Recommendations */
IF OBJECT_ID('recommendations.IndexRecommendations') IS NULL
CREATE TABLE recommendations.IndexRecommendations (
    InstanceId INT,
    DatabaseName SYSNAME,
    TableName SYSNAME,
    RecommendationType VARCHAR(20),
    ImpactScore INT,
    RecommendationSQL NVARCHAR(MAX),
    CollectedOn DATETIME2 DEFAULT SYSDATETIME()
);
GO

/* Power BI Views */
CREATE OR ALTER VIEW vw_DatabaseInventory AS
SELECT
    i.InstanceName,
    i.Environment,
    d.DatabaseName,
    d.Status,
    d.SizeGB,
    d.LastSeen
FROM inventory.Databases d
JOIN inventory.Instances i ON d.InstanceId = i.InstanceId;
GO

CREATE OR ALTER VIEW vw_DatabaseUsageDaily AS
SELECT
    i.InstanceName,
    m.DatabaseName,
    CAST(m.SampleTime AS DATE) AS UsageDate,
    AVG(m.ActiveSessionCount) AS AvgSessions,
    MAX(m.ActiveSessionCount) AS PeakSessions
FROM metrics.DatabaseSessionUsage m
JOIN inventory.Instances i ON m.InstanceId = i.InstanceId
GROUP BY
    i.InstanceName,
    m.DatabaseName,
    CAST(m.SampleTime AS DATE);
GO

PRINT 'SqlMonitorRepo installation completed successfully.';
GO
