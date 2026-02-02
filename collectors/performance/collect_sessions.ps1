
# SQL Server Session Usage Collector
$RepoServer = "SQLMON01"
$RepoDb     = "SqlMonitorRepo"
$Throttle   = 1

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
        SELECT DB_NAME(database_id) AS DatabaseName, COUNT(*) AS ActiveSessionCount
        FROM sys.dm_exec_sessions
        WHERE is_user_process = 1
        GROUP BY database_id
        "

        foreach ($row in $data) {
            Invoke-Sqlcmd -ServerInstance $RepoServer -Database $RepoDb -Query "
            INSERT INTO metrics.DatabaseSessionUsage
            (InstanceId, DatabaseName, ActiveSessionCount, SampleTime)
            VALUES ($($i.InstanceId), '$($row.DatabaseName)', $($row.ActiveSessionCount), SYSDATETIME())
            "
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
            LastErrorMessage='$_'
        WHERE InstanceId=$($i.InstanceId)
        "
    }
}
