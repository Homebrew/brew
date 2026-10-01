# typed: strict
# frozen_string_literal: true

if OS.mac?
  require "extend/os/mac/install"
elsif OS.linux?
  require "extend/os/linux/install"
end
