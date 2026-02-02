<#
.SYNOPSIS
  SQL Server session usage collector (SEQUENTIAL)

.DESCRIPTION
  Collects active user session counts from SQL Server instances
  using direct database connections.
  Compatible with PowerShell 5.1, SSMS PS mode, and SQL Agent.

.RUNAS
  corp\sqlmaintsvc

.SCHEDULE
  Every 5 minutes (SQL Agent)

.NOTES
  Sequential execution (no -Parallel)
#>

$RepoServer = "SQLMON01"
$RepoDb     = "SqlMonitorRepo"

$instances = Invoke-Sqlcmd `
    -ServerInstance $RepoServer `
    -Database $RepoDb `
    -Query "
        SELECT InstanceId, InstanceName
        FROM inventory.Instances
        WHERE IsSuspended = 0
    "

foreach ($i in $instances) {
    try {
        # Mark attempt
        Invoke-Sqlcmd -ServerInstance $RepoServer -Database $RepoDb -Query "
            UPDATE inventory.Instances
            SET LastAttemptTime = SYSDATETIME()
            WHERE InstanceId = $($i.InstanceId)
        "

        # Collect session data from target instance
        $data = Invoke-Sqlcmd `
            -ServerInstance $i.InstanceName `
            -Database master `
            -Query "
                SELECT
                    DB_NAME(database_id) AS DatabaseName,
                    COUNT(*) AS ActiveSessionCount
                FROM sys.dm_exec_sessions
                WHERE is_user_process = 1
                GROUP BY database_id
            "

        foreach ($row in $data) {
            Invoke-Sqlcmd -ServerInstance $RepoServer -Database $RepoDb -Query "
                INSERT INTO metrics.DatabaseSessionUsage
                (InstanceId, DatabaseName, ActiveSessionCount, SampleTime)
                VALUES
                ($($i.InstanceId),
                 '$($row.DatabaseName)',
                 $($row.ActiveSessionCount),
                 SYSDATETIME())
            "
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
        Invoke-Sqlcmd -ServerInstance $RepoServer -Database $RepoDb -Query "
            UPDATE inventory.Instances
            SET
                LastCollectionStatus = 'FAILED',
                LastCollectionTime   = SYSDATETIME(),
                ConsecutiveFailCount = ConsecutiveFailCount + 1,
                LastErrorMessage     = '$($_.Exception.Message)'
            WHERE InstanceId = $($i.InstanceId)
        "
    }
}
