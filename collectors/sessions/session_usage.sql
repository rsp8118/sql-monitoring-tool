-- Collect session usage
SELECT DB_NAME(database_id), COUNT(*) FROM sys.dm_exec_sessions WHERE is_user_process=1 GROUP BY database_id;
