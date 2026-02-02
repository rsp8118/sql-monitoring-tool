
# SQL Server instance inventory collector

$RepoServer = "SQLMON01"
$RepoDb     = "SqlMonitorRepo"

$instances = Invoke-Sqlcmd -ServerInstance $RepoServer -Database $RepoDb -Query "
SELECT InstanceId, InstanceName
FROM inventory.Instances
"

foreach ($i in $instances) {
    try {
        $inv = Invoke-Sqlcmd -ServerInstance $i.InstanceName -Database master -Query "
        SELECT
            CAST(SERVERPROPERTY('ProductVersion') AS varchar(50)) AS ProductVersion,
            CAST(SERVERPROPERTY('Edition') AS varchar(100)) AS Edition,
            windows_release AS OSVersion,
            last_boot_up_time AS LastRebootTime
        FROM sys.dm_os_windows_info
        "

        Invoke-Sqlcmd -ServerInstance $RepoServer -Database $RepoDb -Query "
        UPDATE inventory.Instances
        SET
            SqlVersion   = '$($inv.ProductVersion)',
            Edition      = '$($inv.Edition)',
            OsVersion    = '$($inv.OSVersion)',
            LastRebootTime = '$($inv.LastRebootTime)'
        WHERE InstanceId = $($i.InstanceId)
        "
    } catch {}
}
