#!/usr/bin/ruby

require 'oci8';
require 'benchmark';

#Sqlplus class interact with oracle.
class Sqlplus
	attr_accessor :sqlplus

	#Init Sqplus object with login, password and Hostname
	def initialize(credential)
		@sqlplus = OCI8.new(credential['user'],credential['password'],credential['sid']);
	end

	#Exec query with specific format
	def ExecQuery(sql,formatOutput)
		#Create an Hash to store result
		result = Array.new;

		#Create a cursor with the sql query
		cursor = @sqlplus.parse("#{sql}");

		#Set the column format
		formatOutput.each { | key, value |
			#Define output format
			cursor.define(key,value)
		}

		#Exec the query
		cursor.exec;

		#Store cursor return in hash
		i=0;
		while row = cursor.fetch do
			result.push(row);
		end


		#Return the hash result
		return result;
	end

	#Get time to exec a query
	def timing(sql)
		#Create a cursor with the sql query
		cursor = @sqlplus.parse("#{sql}");

		#get exec time
		time = Benchmark.realtime do
			#Exec the query
			cursor.exec;

			#Close oracle connection
			@sqlplus.logoff;
		end

		#return exec time in milliseconds
		return (time*1000).round(3);
	end

	#Close connection
	def close()
		@sqlplus.logoff;
	end

end
