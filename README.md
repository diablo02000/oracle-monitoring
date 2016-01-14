# oracle-stats
Monitor Oracle Databases

# Description

Oracle stats is a simple tools to get useful metric of your Oracle Database.
Write in ruby, it can return the different metric on the current console or send to graphite.

# Man

```
Help for commands:
  -h          (Optional, takes 0 arguments)
                  Help
  -H          (Required, takes 1 argument)
                  Oracle connection credential
  -go         (Optional, takes 1 argument)
                  Send data to graphite. Set patch to graphite ex: statds.server.sid.
  -so         (Optional, takes 0 arguments)
                  Send data to statsd. Before use this option you need to configure the Statds connection variable.
  -to         (Optional, takes 0 arguments)
                  Console output. This is the default output.
  -connect    (Optional, takes 0 arguments)
                  Get connection time.
  -process_percent (Optional, takes 0 arguments)
                  Get process percentage used.
  -process    (Optional, takes 0 arguments)
                  Get number of running process.
  -session_percent (Optional, takes 0 arguments)
                  Get session percentage.
  -session    (Optional, takes 0 arguments)
                  Get number of running session.
  -library_cache_ratio (Optional, takes 0 arguments)
                  Get Rollback segment hit ratio (gets/waits),  Library Cache (Pin and Get ) Hit Ratio
  -reloads_details (Optional, takes 0 arguments)
                  Get Rollback segment hit ratio (gets/waits),  Library Cache (Pin and Get ) Hit Ratio per namespace.
  -parse_ratio (Optional, takes 0 arguments)
                  Get percentage of parse ratio (Hard/Soft).
  -wait_event_top (Optional, takes 0 arguments)
                  Top 5 wait event.(Average Time)
  -sga        (Optional, takes 0 arguments)
                  Sga memory status (ASMM).
  -cpu        (Optional, takes 0 arguments)
                  Get oracle health.
  -io         (Optional, takes 0 arguments)
                  Get I/O by data files.
  -redo       (Optional, takes 0 arguments)
                  Get redo log activities.
  -temp       (Optional, takes 0 arguments)
                  Get temp activities.
  -datafiles  (Optional, takes 0 arguments)
                  Get datafiles usage.
  -tablespaces (Optional, takes 0 arguments)
                  Get tablespace usage.
  -undo       (Optional, takes 0 arguments)
                  Get undo transaction.
```

## How to Use

Because this script is base on oci8,you have to set TNS_ADMIN variable 

```
# Print the cpu database usage in your shell console
~$ TNS_ADMIN=/path/to/tnsname/dir ./oracle_stats.rb -H nagios/nagios@SID-ORACLE -cpu

# Print the cpu database cpu usage, and send to graphite in  oracle.SID-ORACLE path. 
~$ TNS_ADMIN=/path/to/tnsname/dir ./oracle_stats.rb -H nagios/nagios@SID-ORACLE -go oracle.SID-ORACLE -cpu


```

# Dependency

To run this script you need some gem:

* oci8
* optiflag
* colorize
* graphite-api

For graphite, you need to configure the graphite_credential hash variable

```
graphite_credential = { 'server' => 'graphite.orchestra', 'port' => '2003'};
```

Your oracle user need some grant:
```
GRANT CREATE SESSION TO myUsers;
GRANT SELECT any dictionary TO myUsers;
GRANT SELECT ON V_$SYSSTAT TO myUsers;
GRANT SELECT ON V_$INSTANCE TO myUsers;
GRANT SELECT ON V_$LOG TO myUsers;
GRANT SELECT ON SYS.DBA_DATA_FILES TO myUsers;
GRANT SELECT ON SYS.DBA_FREE_SPACE TO myUsers;
```
