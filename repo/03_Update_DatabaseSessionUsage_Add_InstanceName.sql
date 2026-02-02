
IF COL_LENGTH('metrics.DatabaseSessionUsage','InstanceName') IS NULL
BEGIN
    ALTER TABLE metrics.DatabaseSessionUsage
    ADD InstanceName SYSNAME NULL;
END
GO
