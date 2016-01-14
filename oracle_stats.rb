#!/usr/bin/ruby

########################################
##
## Create script to get statistic data
## from an oracle instance.
##
## This script use oci8,graphite-api,colorized gem.
##
## Before use this script you should set some variable:
##
## - Graphite Hash ( if needed )
## - Collectd Hash ( if needed )
## - Console ( default )
## 
## Man:
## oracle_stats.rb user/password@SID [-go|so|to] bucket -stats_name
##
##########################################


#For ruy 1.8
#require 'rubygems'
require 'optiflag'

#Add own librairy
require_relative 'lib/graphite.rb';
require_relative 'lib/sqlplus.rb';
require_relative 'lib/console.rb'

########################################
### 								 ###
### PLEASE UPDATE HERE  FOR GRAPHITE ###
### 								 ###
########################################
graphite_credential = { 'server' => 'localhost', 'port' => '2003'};

########################################
### 								 ###
### PLEASE UPDATE HERE FOR STATSD    ###
### 								 ###
########################################
statsd_credential = { 'server' => 'localhost', 'port' => '2003'};

# Query hash with all sql query
QUERY = {  'connect' => "SELECT * FROM dual",
	   'process_percent' => "SELECT current_utilization/limit_value*100 FROM v$resource_limit WHERE resource_name LIKE '%processes%'",
	   'process' => "SELECT current_utilization,limit_value FROM v$resource_limit WHERE resource_name LIKE '%processes%'",
	   'session_percent' => "SELECT current_utilization/limit_value*100 FROM v$resource_limit WHERE resource_name = 'sessions'",
	   'session' => "SELECT current_utilization,limit_value FROM v$resource_limit WHERE resource_name = 'sessions'",
	   'get_ratio' => "SELECT sum(GETHITRATIO)*100 FROM GV$librarycache WHERE namespace IN ('SQL AREA') GROUP BY inst_id",
	   'pin_ratio' => "SELECT sum(PINHITRATIO)*100 FROM GV$librarycache WHERE namespace in ('SQL AREA') GROUP BY inst_id",
	   'reloads_ratio' => "SELECT round(((sum(reloads)/sum(pins)) * 100 ),2) from gv$librarycache",
	   'reloads_ratio_details' => "SELECT namespace,sum(pins),sum(reloads),((sum(reloads)/sum(pins)) * 100 ) FROM gv$librarycache WHERE namespace in ('BODY','CLUSTER','INDEX','PIPE','SQL AREA','TABLE/PROCEDURE','TRIGGER') GROUP BY namespace",
	   'hit_ratio' => "SELECT ( 1 - ( pr.value / (dbg.value+cg.value) ) ) *100 FROM v$sysstat pr, v$sysstat dbg, v$sysstat cg WHERE pr.name = 'physical reads' AND dbg.name='db block gets' AND cg.name ='consistent gets'",
	   'parse_ratio' => "select 'Soft',round(((select sum(value) from v$sysstat where name = 'parse count (total)') - (select sum(value) from v$sysstat where name = 'parse count (hard)')) /(select sum(value) from v$sysstat where name = 'execute count') *100,2) from dual union select 'Hard',round( (select sum(value) from v$sysstat where name = 'parse count (hard)') /(select sum(value) from v$sysstat where name = 'execute count') *100,2) from dual",
	   'wait_event' => "SELECT wait_class, SUM(average_wait)/100 as average_wait_sec FROM gv$system_event WHERE wait_class <> 'Idle' GROUP BY WAIT_CLASS ORDER BY 2 DESC",
	   'sga_stats' => "SELECT name,bytes FROM  V$SGAINFO",
	   'oracle_health' => "SELECT DECODE(n.wait_class,'User I/O','User I/O', 'Commit','Commit', 'Wait') CLASS, SUM(ROUND(m.time_waited/m.INTSIZE_CSEC,3)) AAS FROM v$waitclassmetric m, v$system_wait_class n WHERE m.wait_class_id=n.wait_class_id AND n.wait_class    != 'Idle' GROUP BY DECODE(n.wait_class,'User I/O','User I/O', 'Commit','Commit', 'Wait') UNION SELECT 'CPU_ORA_CONSUMED' CLASS, ROUND(value/100,3) AAS FROM v$sysmetric WHERE metric_name='CPU Usage Per Sec' AND group_id     =2 UNION SELECT 'CPU_OS' CLASS , ROUND((prcnt.busy*parameter.cpu_count)/100,3) AAS FROM (SELECT value busy FROM v$sysmetric WHERE metric_name='Host CPU Utilization (%)' AND group_id     =2 ) prcnt, ( SELECT value cpu_count FROM v$parameter WHERE name='cpu_count' ) parameter UNION SELECT 'CPU_ORA_DEMAND' CLASS, NVL(ROUND( SUM(DECODE(session_state,'ON CPU',1,0))/60,2),0) AAS FROM v$active_session_history ash WHERE SAMPLE_TIME > sysdate - (60/(24*60*60))",
	   'io' => "SELECT substr(file_name, instr(file_name,'/',-1)+1,length(file_name)),SUM(phyblkrd),SUM(phyblkwrt) FROM dba_temp_files,v$filestat WHERE file_id=file# GROUP BY tablespace_name,file_name UNION SELECT substr(file_name, instr(file_name,'/',-1)+1,length(file_name)),SUM(phyblkrd), SUM(phyblkwrt) FROM dba_data_files, v$filestat WHERE file_id=file# GROUP BY tablespace_name, file_name",
	   'block_size' => "SELECT value AS block_size FROM v$parameter WHERE name = 'db_block_size'",
	   'redo_switch' => "SELECT count(*) FROM v$log_history WHERE first_time > sysdate - 1/24",
	   'redo_switch_interval' => "WITH redo_log_switch_times AS ( SELECT   sequence#, first_time, LAG (first_time, 1) OVER (ORDER BY first_time) AS LAG, first_time - LAG (first_time, 1) OVER (ORDER BY first_time) lag_time, 1440 * (first_time - LAG (first_time, 1) OVER (ORDER BY first_time)) lag_time_pct_mins FROM v$log_history ORDER BY sequence#) SELECT AVG (lag_time_pct_mins) avg_log_switch_min FROM redo_log_switch_times",
	   'redo_avg_size' => "SELECT AVG(BYTES) FROM v$log",
	   'temp_space' => "SELECT A.tablespace_name tablespace, D.total, SUM (A.used_blocks * D.block_size) used, D.total - SUM (A.used_blocks * D.block_size) free FROM v$sort_segment A,(SELECT B.name,C.block_size, SUM (C.bytes) total FROM v$tablespace B,v$tempfile C WHERE B.ts#= C.ts# GROUP BY B.name,C.block_size) D WHERE A.tablespace_name = D.name GROUP by A.tablespace_name,D.total",
	   'datafiles_space' => "SELECT substr(df.file_name, instr(df.file_name,'/',-1)+1,length(df.file_name)),df.bytes,decode(e.used_bytes,NULL,0,e.used_bytes),decode(f.free_bytes,NULL,0,f.free_bytes),decode(e.used_bytes,NULL,0,Round((e.used_bytes/df.bytes)*100,0))FROM DBA_DATA_FILES DF,(SELECT file_id, sum(bytes) used_bytes FROM dba_extents GROUP by file_id) E,(SELECT Max(bytes) free_bytes,file_id FROM dba_free_space GROUP BY file_id) f WHERE e.file_id (+) = df.file_id AND df.file_id = f.file_id (+) ORDER BY df.tablespace_name,df.file_name",
	   'tablespaces_space' => "SELECT ddf.tablespace_name,SUM( distinct ddf.ddfbytes ),SUM( NVL( ds.bytes , 0 )),ROUND((SUM( distinct ddf.ddfbytes )) - (SUM( NVL( ds.bytes , 0 ))),2),ROUND((SUM( NVL(ds.bytes,0))/SUM( distinct ddf.ddfbytes))*100,2) FROM ( SELECT tablespace_name, SUM( bytes ) ddfbytes FROM dba_data_files GROUP BY tablespace_name ) ddf,dba_segments ds WHERE ddf.tablespace_name = ds.tablespace_name (+) GROUP BY ddf.tablespace_name",
	   'undo_transaction' => "SELECT SUM(t.used_ublk),SUM(t.used_urec),SUM(r.rssize)FROM v$transaction t, v$session s,v$rollstat r,dba_rollback_segs rs WHERE s.saddr = t.ses_addr AND t.xidusn = r.usn AND rs.segment_id = t.xidusn"};


#Create module to parse parameter
#Use optiflag
module OptionParser extend OptiFlagSet
	#Usage for help
	usage_flag "h","help";

	#Hostname (not optional)
	flag "H" do
		description "Oracle connection credential";
		value_matches ["Credential should be username/password@SID",/^\w+\/\w+@\w+$/];
	end

	#Graphite output (optional)
	optional_flag "go" do
		description "Send data to graphite. Set patch to graphite ex: statds.server.sid.";
	end

	#Statsd output(optional)
	optional_flag "so" do
		description "Send data to statsd. Before use this option you need to configure the Statds connection variable.";
		no_arg;
	end

	#Terminal output (default)
	optional_flag "to" do
		description "Console output. This is the default output.";
		no_arg;
	end

	#Stats to get
	optional_flag "connect" do
		description "Get connection time.";
		no_arg;
	end

	optional_flag "process_percent" do
		description "Get process percentage used.";
		no_arg;
	end

	optional_flag "process" do
		description "Get number of running process.";
		no_arg;
	end

	optional_flag "session_percent" do
		description "Get session percentage.";
		no_arg;
	end

	optional_flag "session" do
		description "Get number of running session.";
		no_arg;
	end

	optional_flag "library_cache_ratio" do
		description "Get Rollback segment hit ratio (gets/waits),  Library Cache (Pin and Get ) Hit Ratio";
		no_arg;
	end

	optional_flag "reloads_details" do
		description "Get Rollback segment hit ratio (gets/waits),  Library Cache (Pin and Get ) Hit Ratio per namespace.";
		no_arg;
	end

	optional_flag "parse_ratio" do
		description "Get percentage of parse ratio (Hard/Soft).";
		no_arg;
	end

	optional_flag "wait_event_top" do
		description "Top 5 wait event.(Average Time)";
		no_arg;
	end

	optional_flag "sga" do
		description "Sga memory status (ASMM).";
		no_arg;
	end

	optional_flag "cpu" do
		description "Get oracle health.";
		no_arg;
	end

	optional_flag "io" do
		description "Get I/O by data files.";
		no_arg;
	end

	optional_flag "redo" do
		description "Get redo log activities.";
		no_arg;
	end

	optional_flag "temp" do
		description "Get temp activities.";
		no_arg;
	end

	optional_flag "datafiles" do
		description "Get datafiles usage.";
		no_arg;
	end

	optional_flag "tablespaces" do
		description "Get tablespace usage.";
		no_arg;
	end

	optional_flag "undo" do
		description "Get undo transaction.";
		no_arg;
	end
	#End
	and_process!
end


#Create a login object
def setLoginCredent(credential)
	login = Hash.new;
	login = {	'user' => "#{credential.split(/([a-zA-Z0-9]*(?<!\/))/)[1]}",
          		'password' => "#{credential.split(/([a-zA-Z0-9]*(?<!\/))/)[3]}",
            	'sid' => "#{credential.split(/([a-zA-Z0-9]*(?<!\/))/)[5]}"};
    return login;
end

#Convert bytes to mega
def convertBytesToMega(bytes)
	mb=(bytes/1024/1024)
	return mb.round(2)
end

#Set name output
def setNameOutput(name)
	return name.downcase.gsub(/(\s+|\/)/, "_");
end

#Define error output
console = Console.new();

#Create graphite object if need it
if ARGV.flags.go?
	graphite = Graphite.new(graphite_credential)

	output = "g"
#Create stats object if need it
else
	output = "c"
end

#Test is TNS_ADMIN variable is ( needed with oci8 )
tnsAdmin=ENV['TNS_ADMIN']
if tnsAdmin.nil?
		#Define error message
        message="TNS_ADMIN variable is not set on your environment.
        Please set it with your tnsname.ora path:
        \tex: EXPORT TNS_ADMIN=/usr/local/lib/intance_client/";

        #Print error message
       @console.error(message);

        #Stop script
        exit 2
end

#Create oracle credential hash
loginOracle = setLoginCredent(ARGV.flags.H);

#Create oracle connector
sqlmoins = Sqlplus.new(loginOracle);

# If connect flags is set
if ARGV.flags.connect?
	case output
		when "g"
			data = { "#{ARGV.flags.go}.connect_time"  => "#{sqlmoins.timing(QUERY['connect'])}" };
			graphite.addMetric(data);
		else
			console.print("Connect Time".yellow + " => #{sqlmoins.timing(QUERY['connect'])} ms");
	end
end

# If process_percent flags is set
if ARGV.flags.process_percent?
        #Define the output format
        outputFormat = { 1 => Float };
	result=sqlmoins.ExecQuery(QUERY['process_percent'],outputFormat);

	case output
		when "g"
			data = { "#{ARGV.flags.go}.process.percent"  => "#{result[0].first}" };
			graphite.addMetric(data);
		else
			console.print("Process used".yellow + " => #{result[0].first} %");
	end

	#Close session
	sqlmoins.close()
end

# If process flags is set
if ARGV.flags.process
        #Define the output format
        outputFormat = { 1 => Float };
	result=sqlmoins.ExecQuery(QUERY['process'],outputFormat);

	case output
		when "g"
			data = { "#{ARGV.flags.go}.process.current"  => "#{result[0].first}",
				 "#{ARGV.flags.go}.process.max"  => "#{result[0].last.gsub(/\s+/, "")}"};
			graphite.addMetric(data);
		else
			console.print("Session used".yellow + " => #{result[0].first} / #{result[0].last.gsub(/\s+/, "")}");
	end

	#Close session
	sqlmoins.close()
end

# If session_percent flags is set
if ARGV.flags.session_percent?
        #Define the output format
        outputFormat = { 1 => Float };
	result=sqlmoins.ExecQuery(QUERY['session_percent'],outputFormat);

	case output
		when "g"
			data = { "#{ARGV.flags.go}.session.percent"  => "#{result[0].first.round(2)}"}
			graphite.addMetric(data);
		else
			console.print("Session used".yellow + " => #{result[0].first.round(2)} %");
	end

	#Close session
	sqlmoins.close()
end

# If session flags is set
if ARGV.flags.session?
        #Define the output format
        outputFormat = { 1 => Float };
	result=sqlmoins.ExecQuery(QUERY['session'],outputFormat);

        case output
                when "g"
                        data = { "#{ARGV.flags.go}.session.current"  => "#{result[0].first}",
				 "#{ARGV.flags.go}.session.max"  => "#{result[0].last.gsub(/\s+/, "")}"}
                        graphite.addMetric(data);
                else
                        console.print("Session used".yellow + " => #{result[0].first} / #{result[0].last.gsub(/\s+/, "")}");
        end

	#Close session
	sqlmoins.close()
end

# If hit ratio flags is set
if ARGV.flags.library_cache_ratio?
        #Define the output format
        outputFormat = { 1 => Float };

	#Hit Ratio
	hit=sqlmoins.ExecQuery(QUERY['hit_ratio'],outputFormat);
	pin=sqlmoins.ExecQuery(QUERY['pin_ratio'],outputFormat);
	get=sqlmoins.ExecQuery(QUERY['get_ratio'],outputFormat);
	reloads=sqlmoins.ExecQuery(QUERY['reloads_ratio'],outputFormat);

        case output
                when "g"
                        data = { "#{ARGV.flags.go}.library_cache.hit"  => "#{hit[0].first.round(2)}",
                                 "#{ARGV.flags.go}.library_cache.pin"  => "#{pin[0].first.round(2)}",
                                 "#{ARGV.flags.go}.library_cache.get"  => "#{get[0].first.round(2)}",
                                 "#{ARGV.flags.go}.library_cache.reloads"  => "#{reloads[0].first.round(2)}"}
                        graphite.addMetric(data);
                else
                        console.print("Hit Ratio".yellow + " => #{hit[0].first.round(2)} %");
                        console.print("Pin Ratio".yellow + " => #{pin[0].first.round(2)} %");
        		console.print("Get Ratio".yellow + " => #{get[0].first.round(2)} %")
        		console.print("Reloads Ratio".yellow + " => #{reloads[0].first.round(2)} %")
        end

	#Close session
	sqlmoins.close()
end

#If reload ration detail is set
if ARGV.flags.reloads_details?
	outputFormat = { 2 => Float,3 => Float,4 => Float };
	result=sqlmoins.ExecQuery(QUERY['reloads_ratio_details'],outputFormat);

        case output
                when "g"
			data = Hash.new()
			result.each do | line |
				reloads_sec = "#{setNameOutput(line[0])}"
				data["#{ARGV.flags.go}.reloads.#{reloads_sec}.hits"] = line[1];
				data["#{ARGV.flags.go}.reloads.#{reloads_sec}.misses"] = line[2];
				data["#{ARGV.flags.go}.reloads.#{reloads_sec}.reload_percent"] = line[3];
        		end
                        graphite.addMetric(data);
                else
			result.each do | line |
				console.print("#{setNameOutput(line[0])}".yellow + " => " + "hits".red + ": #{line[1]}, " + "Misses".red + ": #{line[2]}, " + "Reload".red + ": #{line[3].round(2)} %")
			end
        end

end

#If parse ratio is selected
if ARGV.flags.parse_ratio?
	#Sql output Format
	outputFormat = { 2 => Float };
	result=sqlmoins.ExecQuery(QUERY['parse_ratio'],outputFormat);

	case output
                when "g"
                        data = Hash.new()
                        result.each do | line |
                                parse_ratio = "#{setNameOutput(line[0])}"
                                data["#{ARGV.flags.go}.parse_ratio.#{parse_ratio}"] = line[1];
                        end

                        graphite.addMetric(data);
                else
                        result.each do | line |
                                console.print("#{setNameOutput(line[0])}".yellow + " => #{line[1]} %")
                        end
        end
end

#If wait event is selected
if ARGV.flags.wait_event_top?
	#Sql Output format
	outputFormat = { 2 => Float };
	result=sqlmoins.ExecQuery(QUERY['wait_event'],outputFormat);


        case output
                when "g"
                        data = Hash.new()
                        result.each do | line |
                                wait = "#{setNameOutput(line[0])}"
                                data["#{ARGV.flags.go}.wait_event.#{wait}"] = line[1].round(2);
                        end
                        graphite.addMetric(data);
                else
                        result.each do | line |
                                console.print("#{setNameOutput(line[0])}".yellow + " => #{line[1].round(2)}"+ " Secondes".red)
                        end
        end
end

#If sga is selected
if ARGV.flags.sga?
	#Sql Output format
	outputFormat = { 2 => Float};
	result=sqlmoins.ExecQuery(QUERY['sga_stats'],outputFormat);

        case output
                when "g"
                        data = Hash.new()
                        result.each do | line |
                                sgaComponent = "#{setNameOutput(line[0])}"
                                data["#{ARGV.flags.go}.sga.#{sgaComponent}"] = line[1].round(2);
                        end
                        graphite.addMetric(data);
                else
                        result.each do | line |
				console.print("#{setNameOutput(line[0])}".yellow + " => " + ": #{convertBytesToMega(line[1])} Mb")
                        end
        end
end

#If cpu is selected
if ARGV.flags.cpu?
	#Define Constant
	KEY=0
	VALUE=1

	#Sql Output format
	outputFormat = { 2 => Float };
	result=sqlmoins.ExecQuery(QUERY['oracle_health'],outputFormat);

        case output
                when "g"
                        data = Hash.new()
                        result.each do | line |
                                cpuComponent = "#{setNameOutput(line[KEY])}"
                                data["#{ARGV.flags.go}.cpu.#{cpuComponent}"] = line[1].round(2);
                        end
                        graphite.addMetric(data);
                else
                        result.each do | line |
				console.print("#{setNameOutput(line[KEY])}".yellow + " => #{line[VALUE]} ")
                        end
        end
end

#If io is selected
if ARGV.flags.io?
	#Define Constanst
	DFNAME=0
	READ=1
	WRITE=2

	#Get block size set in oracle instance
	outputFormat = { 1 => Float };
	blockSize = sqlmoins.ExecQuery(QUERY['block_size'],outputFormat)[0][0];

	outputFormat = { 2 => Float, 3 => Float };

	#First run
	firstTimeStamp=Time.now.getutc;
	firstGet=sqlmoins.ExecQuery(QUERY['io'],outputFormat);

	#Second run
	secTimeStamp=Time.now.getutc;
	secGet=sqlmoins.ExecQuery(QUERY['io'],outputFormat);

	#Delta timestamp
	deltaTimestamp = secTimeStamp - firstTimeStamp;
 
	
	#Output result
        case output
                when "g"
                        data = Hash.new()

			#For each line
			firstGet.each do | lineFirst |
				secGet.each do | lineSec |
					#If same datafile
					if "#{lineFirst[DFNAME]}" == "#{lineSec[DFNAME]}"
						deltaRead = lineSec[READ] - lineFirst[READ];
						deltaWrite = lineSec[WRITE] - lineFirst[WRITE];
		
						mbps = convertBytesToMega((((deltaRead + deltaWrite)/deltaTimestamp) * blockSize))
		
						#Output
                                		data["#{ARGV.flags.go}.io.#{lineSec[DFNAME].gsub(/\.dbf/,'')}"] = mbps;
					end	
				end
			end

                        graphite.addMetric(data);
                else
			#For each line
			firstGet.each do | lineFirst |
				secGet.each do | lineSec |
					#If same datafile
					if "#{lineFirst[DFNAME]}" == "#{lineSec[DFNAME]}"
						deltaRead = lineSec[READ] - lineFirst[READ];
						deltaWrite = lineSec[WRITE] - lineFirst[WRITE];
		
						mbps = convertBytesToMega((((deltaRead + deltaWrite)/deltaTimestamp) * blockSize))
		
						#Output
						console.print("#{lineSec[DFNAME]}".yellow + " => #{mbps} " + "Mb / Sec".red)
					end	
				end
			end
        end

end

#If redo is selected
if ARGV.flags.redo?
	#Define Constant
	VALUE=0

	#Define output format
	outputFormat = { 1 => Float };

	#Redo / hour
	redoPerHour = sqlmoins.ExecQuery(QUERY['redo_switch'],outputFormat).first;

	#Redo switch interval
	redoSwitchInterval = sqlmoins.ExecQuery(QUERY['redo_switch_interval'],outputFormat).first;

	#Redo conso avg
	result = sqlmoins.ExecQuery(QUERY['redo_avg_size'],outputFormat);
	redoAvgIO = convertBytesToMega((redoPerHour[VALUE] * result.first[VALUE])/60)

        case output
                when "g"
                        data = Hash.new()
                        
			#Store data        
			data["#{ARGV.flags.go}.redo.nbr_switch"] = redoPerHour[VALUE];
			data["#{ARGV.flags.go}.redo.switch_every"] = redoSwitchInterval[VALUE].round(2);
			data["#{ARGV.flags.go}.redo.redo_mbpm"] = redoAvgIO;

                        graphite.addMetric(data);
                else
			console.print("nbr_switch".yellow + " => #{redoPerHour[VALUE]}" + " / Hour".red)
			console.print("switch_every".yellow + " => #{redoSwitchInterval[VALUE].round(2)}" + " Minutes".red)
			console.print("redo_log_activitie".yellow + " => #{redoAvgIO}" + " Mb/min".red);
        end

end

#If temp is selected
if ARGV.flags.temp?
	#Define output format
	outputFormat = { 2 => Float, 3 => Float, 4 => Float };
	result = sqlmoins.ExecQuery(QUERY['temp_space'],outputFormat).first;

        case output
                when "g"
                        data = Hash.new()

                        #Store data        
                        data["#{ARGV.flags.go}.temp.total"] = convertBytesToMega(result[1]);
                        data["#{ARGV.flags.go}.temp.used"] = convertBytesToMega(result[2]);
                        data["#{ARGV.flags.go}.temp.free"] = convertBytesToMega(result[3]);

                        graphite.addMetric(data);
                else
			total = convertBytesToMega(result[1]);
			used = convertBytesToMega(result[2]);
			free = convertBytesToMega(result[3]);
		
			console.print("Tablespace #{result[0]}".yellow + " => Total: #{total}" + " Mb".red + ", Used: #{used}" + " Mb".red + ", Free: #{free}" + " Mb".red);
        end


end


#If datafile is selected
if ARGV.flags.datafiles?
	#Define output format
	outputFormat = { 2 => Float, 3 => Float, 4 => Float, 5 => Float };
	result = sqlmoins.ExecQuery(QUERY['datafiles_space'],outputFormat);

        case output
                when "g"
                        data = Hash.new()

			result.each do | line |
				
                        	#Store data        
                        	data["#{ARGV.flags.go}.datafiles.#{line[0].gsub(/\.dbf/,'')}_total"] = line[1];
                        	data["#{ARGV.flags.go}.datafiles.#{line[0].gsub(/\.dbf/,'')}_used"] = line[2];
                        	data["#{ARGV.flags.go}.datafiles.#{line[0].gsub(/\.dbf/,'')}_free"] = line[3];
                        	data["#{ARGV.flags.go}.datafiles.#{line[0].gsub(/\.dbf/,'')}_used_percent"] = line[4];
				
			end

                        puts data
                        #graphite.addMetric(data);
                else
			result.each do | line |
                        	total = convertBytesToMega(line[1]);
                        	used = convertBytesToMega(line[2]);
                        	free = convertBytesToMega(line[3]);

				console.print("Datafile #{line[0]}".yellow + " => Total: #{total}" + " Mb".red + ", Used: #{used}" + " Mb".red + ", Free: #{free}" + " Mb".red + ", % Used: #{line[4]}" + " %".red);
			end
        end
end

#If tablespace is selected
if ARGV.flags.tablespaces?
	#Define output format
	outputFormat = { 2 => Float, 3 => Float, 4 => Float, 5 => Float };
	result = sqlmoins.ExecQuery(QUERY['tablespaces_space'],outputFormat);

        case output
                when "g"
                        data = Hash.new()

                        result.each do | line |

                                #Store data        
                                data["#{ARGV.flags.go}.tablespace.#{line[0].downcase}_total"] = line[1];
                                data["#{ARGV.flags.go}.tablespace.#{line[0].downcase}_used"] = line[2];
                                data["#{ARGV.flags.go}.tablespace.#{line[0].downcase}_free"] = line[3];
                                data["#{ARGV.flags.go}.tablespace.#{line[0].downcase}_used_percent"] = line[4];

                        end

                        graphite.addMetric(data);
                else
                        result.each do | line |
                                total = convertBytesToMega(line[1]);
                                used = convertBytesToMega(line[2]);
                                free = convertBytesToMega(line[3]);

                                console.print("Tablespace #{line[0].downcase}".yellow + " => Total: #{total}" + " Mb".red + ", Used: #{used}" + " Mb".red + ", Free: #{free}" + " Mb".red + ", % Used: #{line[4]}" + " %".red);
                        end
        end
end

#If undo is selected
if ARGV.flags.undo?
	#Define output format
	outputFormat = { 1 => Float };
	blockSize = sqlmoins.ExecQuery(QUERY['block_size'],outputFormat).first[0];

	#Define output format
	outputFormat = { 1 => Float, 2 => Float, 3 => Float };
	undoTransaction = sqlmoins.ExecQuery(QUERY['undo_transaction'],outputFormat).first;

	
	#Convert block to Gb
	if ! "#{undoTransaction[0]}".empty?
		blockUsed = ((undoTransaction[0] * blockSize)/1024/1024).round(2)
	else
		blockUsed = 0
	end

	if ! "#{undoTransaction[1]}".empty?
		blockRecord = ((undoTransaction[1] * blockSize)/1024/1024).round(2)
	else
		blockRecord = 0
	end

	if ! "#{undoTransaction[2]}".empty?
		rollbackSegment = (undoTransaction[2]/1024/1024).round(2)
	else
		rollbackSegment = 0
	end

        case output
                when "g"
                        data = Hash.new()

                        #Store data        
                        data["#{ARGV.flags.go}.undo.used"] = blockUsed;
                        data["#{ARGV.flags.go}.tablespace.record"] = blockRecord;
                        data["#{ARGV.flags.go}.tablespace.rollback"] = rollbackSegment;

                        graphite.addMetric(data);
                else
			console.print("Undo Transaction".yellow + " => Used : #{blockUsed} " + " Mb".red + ", Record : #{blockRecord}" + " Mb".red + ", Rollback : #{rollbackSegment} " + "Mb".red); 
        end


	
end
