# typed: strict
# frozen_string_literal: true

if OS.mac?
  require "extend/os/mac/development_tools"
elsif OS.linux?
  require "extend/os/linux/development_tools"
end
