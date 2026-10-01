# typed: strict
# frozen_string_literal: true

require "extend/os/mac/cask/config" if OS.mac?
require "extend/os/linux/cask/config" if OS.linux?
