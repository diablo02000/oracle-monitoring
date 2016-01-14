require 'colorize'

class Console
	def print(text)
		puts "#{text}"
	end

	def error(text)
		puts "#{"ERROR:".bold} #{text}".red
	end

	def warning(text)
		puts "#{"WARNING:".bold} #{text}".yellow
	end

end
