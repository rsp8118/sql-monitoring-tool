
# SQL Server session usage collector (SEQUENTIAL, RESILIENT)

$RepoServer = "SQLMON01"
$RepoDb     = "SqlMonitorRepo"

$instances = Invoke-Sqlcmd -ServerInstance $RepoServer -Database $RepoDb -Query "
SELECT InstanceId, InstanceName
FROM inventory.Instances
WHERE IsSuspended = 0
"

foreach ($i in $instances) {
    try {
        Invoke-Sqlcmd -ServerInstance $RepoServer -Database $RepoDb -Query "
        UPDATE inventory.Instances
        SET LastAttemptTime = SYSDATETIME()
        WHERE InstanceId = $($i.InstanceId)
        "

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

        Invoke-Sqlcmd -ServerInstance $RepoServer -Database $RepoDb -Query "
        UPDATE inventory.Instances
        SET LastCollectionStatus='SUCCESS',
            LastCollectionTime=SYSDATETIME(),
            ConsecutiveFailCount=0,
            LastErrorMessage=NULL
        WHERE InstanceId=$($i.InstanceId)
        "
    }
    catch {
        Invoke-Sqlcmd -ServerInstance $RepoServer -Database $RepoDb -Query "
        UPDATE inventory.Instances
        SET LastCollectionStatus='FAILED',
            LastCollectionTime=SYSDATETIME(),
            ConsecutiveFailCount=ConsecutiveFailCount+1,
            LastErrorMessage='$($_.Exception.Message)'
        WHERE InstanceId=$($i.InstanceId)
        "
    }
}
