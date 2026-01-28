# typed: strict
# frozen_string_literal: true

if OS.mac?
  require "extend/os/mac/linkage_checker"
else
  require "extend/os/linux/linkage_checker"
end
