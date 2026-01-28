# typed: strict
# frozen_string_literal: true

if OS.mac?
  require "extend/os/mac/dependency_collector"
elsif OS.linux?
  require "extend/os/linux/dependency_collector"
end
