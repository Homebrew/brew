# typed: strict
# frozen_string_literal: true

if OS.mac?
  require "extend/os/mac/simulate_system"
elsif OS.linux?
  require "extend/os/linux/simulate_system"
end
