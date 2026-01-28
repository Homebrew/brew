# typed: strict
# frozen_string_literal: true

if OS.mac?
  require "extend/os/mac/formula"
elsif OS.linux?
  require "extend/os/linux/formula"
end
