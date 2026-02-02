
<#
.SYNOPSIS
  SQL Server session usage collector (SEQUENTIAL, FAULT-TOLERANT)

.DESCRIPTION
  - Continues to NEXT instance on ANY connection/query error
  - No Invoke-Sqlcmd failure can stop the loop
  - Collects ONLY user databases
  - Stores InstanceName in metrics
  - PowerShell 5.1 / SQL Agent safe
#>

$RepoServer = "SQLMON01"
$RepoDb     = "SqlMonitorRepo"

$instances = Invoke-Sqlcmd -ServerInstance $RepoServer -Database $RepoDb -Query "
SELECT InstanceId, InstanceName
FROM inventory.Instances
WHERE IsSuspended = 0
"

foreach ($i in $instances) {

    try {
        # Mark attempt (never blocks next instance)
        try {
            Invoke-Sqlcmd -ServerInstance $RepoServer -Database $RepoDb -Query "
                UPDATE inventory.Instances
                SET LastAttemptTime = SYSDATETIME()
                WHERE InstanceId = $($i.InstanceId)
            "
        } catch {}

        # TRY connecting to target instance
        try {
            $data = Invoke-Sqlcmd -ServerInstance $i.InstanceName -Database master -Query "
                SELECT
                    DB_NAME(s.database_id) AS DatabaseName,
                    COUNT(*) AS ActiveSessionCount
                FROM sys.dm_exec_sessions s
                JOIN sys.databases d ON s.database_id = d.database_id
                WHERE s.is_user_process = 1
                  AND d.database_id > 4
                GROUP BY s.database_id
            " -ErrorAction Stop
        }
        catch {
            # Log failure and CONTINUE to next instance
            Invoke-Sqlcmd -ServerInstance $RepoServer -Database $RepoDb -Query "
                UPDATE inventory.Instances
                SET
                    LastCollectionStatus = 'FAILED',
                    LastCollectionTime   = SYSDATETIME(),
                    ConsecutiveFailCount = ConsecutiveFailCount + 1,
                    LastErrorMessage     = 'Connection or query failed'
                WHERE InstanceId = $($i.InstanceId)
            "
            continue
        }

        # Insert collected rows (row-level isolation)
        foreach ($row in $data) {
            try {
                Invoke-Sqlcmd -ServerInstance $RepoServer -Database $RepoDb -Query "
                    INSERT INTO metrics.DatabaseSessionUsage
                    (InstanceId, InstanceName, DatabaseName, ActiveSessionCount, SampleTime)
                    VALUES
                    ($($i.InstanceId),
                     '$($i.InstanceName)',
                     '$($row.DatabaseName)',
                     $($row.ActiveSessionCount),
                     SYSDATETIME())
                "
            } catch {}
        }

        # Success update
        Invoke-Sqlcmd -ServerInstance $RepoServer -Database $RepoDb -Query "
            UPDATE inventory.Instances
            SET
                LastCollectionStatus = 'SUCCESS',
                LastCollectionTime   = SYSDATETIME(),
                ConsecutiveFailCount = 0,
                LastErrorMessage     = NULL
            WHERE InstanceId = $($i.InstanceId)
        "
    }
    catch {
        # Absolute safety net – never stop loop
        continue
    }
}
