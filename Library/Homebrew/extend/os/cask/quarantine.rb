# typed: strict
# frozen_string_literal: true

require "extend/os/mac/cask/quarantine" if OS.mac?
require "extend/os/linux/cask/quarantine" if OS.linux?
