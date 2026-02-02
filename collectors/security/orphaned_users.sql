-- Detect orphaned users
SELECT name FROM sys.database_principals WHERE sid NOT IN (SELECT sid FROM sys.server_principals);
