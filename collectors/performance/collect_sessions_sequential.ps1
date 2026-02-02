
# SQL Server session usage collector (AGGREGATED: Instance + DB + Login + State)

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
    } catch {}

    try {
        $agg = Invoke-Sqlcmd -ServerInstance $i.InstanceName -Database master -Query "
        SELECT
            DB_NAME(s.database_id) AS DatabaseName,
            s.login_name           AS LoginName,
            CASE 
                WHEN r.session_id IS NULL THEN 'INACTIVE'
                ELSE 'ACTIVE'
            END AS SessionState,
            COUNT(*) AS SessionCount
        FROM sys.dm_exec_sessions s
        LEFT JOIN sys.dm_exec_requests r
            ON s.session_id = r.session_id
        JOIN sys.databases d
            ON s.database_id = d.database_id
        WHERE
            s.is_user_process = 1
            AND d.database_id > 4
        GROUP BY
            s.database_id,
            s.login_name,
            CASE 
                WHEN r.session_id IS NULL THEN 'INACTIVE'
                ELSE 'ACTIVE'
            END
        " -ErrorAction Stop
    }
    catch {
        Invoke-Sqlcmd -ServerInstance $RepoServer -Database $RepoDb -Query "
            UPDATE inventory.Instances
            SET LastCollectionStatus='FAILED',
                LastCollectionTime=SYSDATETIME(),
                ConsecutiveFailCount = ConsecutiveFailCount + 1,
                LastErrorMessage='Session aggregation failed'
            WHERE InstanceId=$($i.InstanceId)
        "
        continue
    }

    foreach ($row in $agg) {
        try {
            Invoke-Sqlcmd -ServerInstance $RepoServer -Database $RepoDb -Query "
            INSERT INTO metrics.DatabaseSessionUsage
            (InstanceId, InstanceName, DatabaseName, LoginName, SessionState, ActiveSessionCount, SampleTime)
            VALUES
            ($($i.InstanceId),
             '$($i.InstanceName)',
             '$($row.DatabaseName)',
             '$($row.LoginName)',
             '$($row.SessionState)',
             $($row.SessionCount),
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
