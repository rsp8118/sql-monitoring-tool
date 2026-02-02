
This update adds:
- Session usage collector (PowerShell)
- Suspension & retry metadata columns
- Sequential (Throttle=1) safe execution model

Steps:
1. Run repo/01_Update_Instances_Suspension.sql on SqlMonitorRepo
2. Commit collectors/performance/collect_sessions.ps1
3. Test via SSMS PowerShell mode
4. Schedule via SQL Agent
