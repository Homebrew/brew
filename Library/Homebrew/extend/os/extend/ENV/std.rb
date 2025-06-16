# typed: strict
# frozen_string_literal: true

if OS.mac?
  require "extend/os/mac/extend/ENV/std"
elsif OS.linux?
  require "extend/os/linux/extend/ENV/std"
end
