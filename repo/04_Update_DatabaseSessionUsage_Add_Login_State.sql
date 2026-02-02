
IF COL_LENGTH('metrics.DatabaseSessionUsage','LoginName') IS NULL
    ALTER TABLE metrics.DatabaseSessionUsage ADD LoginName SYSNAME NULL;
IF COL_LENGTH('metrics.DatabaseSessionUsage','SessionState') IS NULL
    ALTER TABLE metrics.DatabaseSessionUsage ADD SessionState VARCHAR(10) NULL;
GO
