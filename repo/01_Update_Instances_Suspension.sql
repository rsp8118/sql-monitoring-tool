
ALTER TABLE inventory.Instances
ADD
    IsSuspended BIT NOT NULL DEFAULT 0,
    SuspendedOn DATETIME2 NULL,
    ConsecutiveFailCount INT NOT NULL DEFAULT 0,
    LastAttemptTime DATETIME2 NULL,
    LastCollectionStatus VARCHAR(20) NULL,
    LastCollectionTime DATETIME2 NULL,
    LastErrorMessage NVARCHAR(4000) NULL;
GO
