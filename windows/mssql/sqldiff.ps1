 <#
.SYNOPSIS
  Script to run scheduled SQL incremental backup and run new full on databases missing full backup
.DESCRIPTION

.PARAMETER Verbose
Provides Verbose output which is useful for troubleshooting
.EXAMPLE
  <Example goes here. Repeat this attribute for more than one example>
.INPUTS
  None
.OUTPUTS
  None
.NOTES
  Version:        1.0
  Author:         Christian Petersson
  Company:        IssTech AB
  Creation Date:  2023-03-06
  Purpose/Change: Initial script development
#>


function Get-TimeStamp {
    
    return "{0:yyyy-MM-dd} {0:HH:mm:ss}" -f (Get-Date)    

}

$fcm_path = "C:\Program Files\Tivoli\FlashCopyManager"
$optfile = "C:\Program Files\Tivoli\TSM\TDPSql\dsm.opt"
$sched_log = "C:\Program Files\Tivoli\TSM\TDPSql\sqlsched.opt"
$sqlfull = "C:\Program Files\Tivoli\TSM\TDPSql\sqlfull.log"
$sqllog = "C:\Program Files\Tivoli\TSM\TDPSql\sqllog.log"
$sqldiff = "C:\Program Files\Tivoli\TSM\TDPSql\sqldiff.log"
$MissingFullQuery = "SET NOCOUNT ON SELECT master.dbo.sysdatabases.NAME AS database_name, NULL AS [Last Data Backup Date], 9999 AS [Backup Age (Hours)] 
                    FROM master.dbo.sysdatabases LEFT JOIN msdb.dbo.backupset ON master.dbo.sysdatabases.name = msdb.dbo.backupset.database_name 
                    WHERE msdb.dbo.backupset.database_name IS NULL AND master.dbo.sysdatabases.name <> 'tempdb' 
                    ORDER BY msdb.dbo.backupset.database_name"

$sqlinstance = (get-itemproperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server').InstalledInstances
$defaultinstance = $sqlinstance | Where-Object {$_ -eq "MSSQLSERVER"}
$namedinstance = $sqlinstance | Where-Object {$_ -ne "MSSQLSERVER"}

### Import Cmdlets for protecting Microsoft SQL Server data ###
dir "$fcm_path\fmmodule*.dll" | select -expand fullname | import-module 

### Checks for running backups ###

$runninbackup = Get-WmiObject Win32_Process -Filter "name = 'powershell.exe'" | Select-Object CommandLine

if ($runninbackup.CommandLine -like "*sqlfull*") {
    Write-Output "$(Get-TimeStamp) Skipping diff, full backup alredy running" | Out-file  -Encoding UTF8 -FilePath $sqldiff -Append
    exit 0
}

if ($runninbackup.CommandLine -like '*sqllog*') {
    Write-Output "$(Get-TimeStamp) Skipping diff, log backup alredy running" | Out-file  -Encoding UTF8 -FilePath $sqldiff -Append
    exit 0
}

$sqlinstance = (get-itemproperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server').InstalledInstances

### Run full backup on database with missing full ###
$startTime = Get-TimeStamp

if ($defaultinstance){
    foreach ($di in $defaultinstance) {
        $MissingFullBackup = Invoke-SQLCMD -server "$($env:COMPUTERNAME)" -Query $MissingFullQuery
        if ($MissingFullBackup){
            foreach ($dd in $MissingFullBackup){Backup-DpSqlComponent -Name $($dd.database_name) -SqlServer "$($env:COMPUTERNAME)" -Full -TsmOptFile $optfile -LogFile $sqlfull}
        }
        Backup-DpSqlComponent -Name * -DiffFull -TsmOptFile $optfile -LogFile $sqldiff
    }
}

### Checks if named instance exists and run full backup on databases missing full then run normal diff backup ###

if ($namedinstance){
    foreach ($ni in $namedinstance) {
        $MissingFullBackup = Invoke-SQLCMD -server "$($env:COMPUTERNAME)\$($ni)" -Query $MissingFullQuery
        if ($MissingFullBackup){
            foreach ($nd in $MissingFullBackup){Backup-DpSqlComponent -Name $($nd.database_name) -SqlServer "$($env:COMPUTERNAME)\$($ni)" -Full -TsmOptFile $optfile -LogFile $sqlfull}
        }
        Backup-DpSqlComponent -Name * -SqlServer "$($env:COMPUTERNAME)\$($ni)" -DiffFull -TsmOptFile $optfile -LogFile $sqldiff
    }
} 
