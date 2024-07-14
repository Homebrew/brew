require "json"

module Whirly
  module Spinners
    CLI = JSON.load(File.read(File.dirname(__FILE__) + "/../../../data/cli-spinners.json")).freeze
  end
end
