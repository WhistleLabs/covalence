require 'yaml'

require_relative '../../covalence'

Dir[File.expand_path("cli_wrappers/**/*.rb", File.dirname(__FILE__))].sort.each { |file| require file }
Dir[File.expand_path("entities/**/*.rb", File.dirname(__FILE__))].sort.each { |file| require file }
Dir[File.expand_path("repositories/**/*.rb", File.dirname(__FILE__))].sort.each { |file| require file }
Dir[File.expand_path("services/**/*.rb", File.dirname(__FILE__))].sort.each { |file| require file }
