# typed: strict
# frozen_string_literal: true

if OS.mac?
  require "extend/os/mac/system_config"
elsif OS.linux?
  require "extend/os/linux/system_config"
end
