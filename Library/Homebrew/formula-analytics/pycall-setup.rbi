# typed: strict

class InfluxDBClient3
  def self.initialize(*args); end

  def query(*args); end
end

module PyCall
  def self.init(*args); end

  module Import
    def self.pyfrom(*args); end

    def self.import(*args); end
  end

  PyError = Class.new(StandardError).freeze
end

# Needs defined here for Sorbet to work as expected.
# rubocop:disable Style/TopLevelMethodDefinition
def pyfrom(*args); end
# rubocop:enable Style/TopLevelMethodDefinition
