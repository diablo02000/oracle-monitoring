#########################################
##
## Create lib to send metric to graphite.
## This lib use graphite-api.
##
###########################################

#Require graphite-api gem
#https://rubygems.org/gems/graphite-api
require 'graphite-api'


#Create class Graphite
class Graphite
	attr_accessor :graphite

	#Init Graphite object with host and port ( default 2003 )
	def initialize(cred)
		@graphite = GraphiteAPI.new( 
				graphite: "#{cred['server']}:#{cred['port']}",
				prefix: ["stats","gauges"]);
	end

	#Send metric to gaphite. Data object
	#should be an array of hash with 'bucket' => 'value'
	def addMetric(data)
		data.each { | key, value|
			@graphite.metrics("#{key}" => value);
		}
	end


	#Send metric to gaphite with specific timestamp. Data object
	#should be an array of hash with 'bucket' => 'value'
	def addMetricWithTimestamp(data,timestamp)
		data.each { | key, value|
			@graphite.metrics({"#{key}" => value},timestamp);
		}
	end
end
