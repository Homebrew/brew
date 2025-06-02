# typed: strict
# frozen_string_literal: true

if OS.mac?
  require "extend/os/mac/keg"
elsif OS.linux?
  require "extend/os/linux/keg"
end
