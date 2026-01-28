# typed: strict
# frozen_string_literal: true

if OS.mac?
  require "extend/os/mac/formula_installer"
elsif OS.linux?
  require "extend/os/linux/formula_installer"
end
