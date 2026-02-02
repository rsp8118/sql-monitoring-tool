
# SQL Server session usage collector (ACTIVE + INACTIVE, NOT NULL SAFE)

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
        $sessions = Invoke-Sqlcmd -ServerInstance $i.InstanceName -Database master -Query "
        SELECT
            s.login_name,
            DB_NAME(s.database_id) AS DatabaseName,
            CASE 
                WHEN r.session_id IS NULL THEN 'INACTIVE'
                ELSE 'ACTIVE'
            END AS SessionState
        FROM sys.dm_exec_sessions s
        LEFT JOIN sys.dm_exec_requests r
            ON s.session_id = r.session_id
        JOIN sys.databases d
            ON s.database_id = d.database_id
        WHERE
            s.is_user_process = 1
            AND d.database_id > 4
        " -ErrorAction Stop
    }
    catch {
        Invoke-Sqlcmd -ServerInstance $RepoServer -Database $RepoDb -Query "
            UPDATE inventory.Instances
            SET LastCollectionStatus='FAILED',
                LastCollectionTime=SYSDATETIME(),
                ConsecutiveFailCount = ConsecutiveFailCount + 1,
                LastErrorMessage='Session query failed'
            WHERE InstanceId=$($i.InstanceId)
        "
        continue
    }

    foreach ($row in $sessions) {
        try {
            Invoke-Sqlcmd -ServerInstance $RepoServer -Database $RepoDb -Query "
            INSERT INTO metrics.DatabaseSessionUsage
            (InstanceId, InstanceName, DatabaseName, LoginName, SessionState, ActiveSessionCount, SampleTime)
            VALUES
            ($($i.InstanceId),
             '$($i.InstanceName)',
             '$($row.DatabaseName)',
             '$($row.login_name)',
             '$($row.SessionState)',
             CASE WHEN '$($row.SessionState)' = 'ACTIVE' THEN 1 ELSE 0 END,
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
