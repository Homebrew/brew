# typed: strict
# frozen_string_literal: true

if OS.mac?
  require "extend/os/mac/extend/pathname"
elsif OS.linux?
  require "extend/os/linux/extend/pathname"
end
