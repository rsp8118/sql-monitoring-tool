<#
.SYNOPSIS
  SQL Server session usage collector

.DESCRIPTION
  Collects active user session counts from SQL Server instances
  using direct database connections (no linked servers).

.AUTHOR
  DBA Team

.RUNAS
  corp\sqlmaintsvc

.SCHEDULE
  Every 5 minutes (SQL Agent)

.NOTES
  Start with Throttle = 1, increase later (e.g. 5)
#>

$RepoServer = "SQLMON01"
$RepoDb     = "SqlMonitorRepo"
$Throttle   = 1   # start sequential

$instances = Invoke-Sqlcmd `
    -ServerInstance $RepoServer `
    -Database $RepoDb `
    -Query "
        SELECT InstanceId, InstanceName
        FROM inventory.Instances
        WHERE IsSuspended = 0
    "

$instances | ForEach-Object -Parallel {

    param ($RepoServer, $RepoDb)

    try {
        Invoke-Sqlcmd -ServerInstance $RepoServer -Database $RepoDb -Query "
            UPDATE inventory.Instances
            SET LastAttemptTime = SYSDATETIME()
            WHERE InstanceId = $($_.InstanceId)
        "

        $data = Invoke-Sqlcmd `
            -ServerInstance $_.InstanceName `
            -Database master `
            -Query "
                SELECT
                    DB_NAME(database_id) AS DatabaseName,
                    COUNT(*) AS ActiveSessionCount
                FROM sys.dm_exec_sessions
                WHERE is_user_process = 1
                GROUP BY database_id
            " `
            -ErrorAction Stop

        foreach ($row in $data) {
            Invoke-Sqlcmd `
                -ServerInstance $RepoServer `
                -Database $RepoDb `
                -Query "
                    INSERT INTO metrics.DatabaseSessionUsage
                    (InstanceId, DatabaseName, ActiveSessionCount, SampleTime)
                    VALUES
                    ($($_.InstanceId),
                     '$($row.DatabaseName)',
                     $($row.ActiveSessionCount),
                     SYSDATETIME())
                "
        }

        Invoke-Sqlcmd -ServerInstance $RepoServer -Database $RepoDb -Query "
            UPDATE inventory.Instances
            SET
                LastCollectionStatus = 'SUCCESS',
                LastCollectionTime   = SYSDATETIME(),
                ConsecutiveFailCount = 0,
                LastErrorMessage     = NULL
            WHERE InstanceId = $($_.InstanceId)
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
            WHERE InstanceId = $($_.InstanceId)
        "

        Invoke-Sqlcmd -ServerInstance $RepoServer -Database $RepoDb -Query "
            UPDATE inventory.Instances
            SET IsSuspended = 1, SuspendedOn = SYSDATETIME()
            WHERE InstanceId = $($_.InstanceId)
              AND ConsecutiveFailCount >= 5
        "
    }

} -ThrottleLimit $Throttle -ArgumentList $RepoServer, $RepoDb
