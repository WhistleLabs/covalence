# Modularize dependencies around the rspec tasks
require 'rubygems'

module Covalence
  module Helpers
    class SpecDependencies
      def self.dependencies
        {
          "ci_reporter_rspec" => "~> 1.0.0",
          "rspec" => "~> 3.5"
        }
      end

      def self.check_dependencies
        self.dependencies.each do |name, requirement|
          Gem::Specification.find_by_name(name, requirement)
        end
      end
    end
  end
end
