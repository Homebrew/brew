# typed: strict
# frozen_string_literal: true

if OS.mac?
  require "extend/os/mac/cleanup"
elsif OS.linux?
  require "extend/os/linux/cleanup"
end
