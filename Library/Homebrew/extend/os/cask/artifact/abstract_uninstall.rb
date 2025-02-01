# typed: strict
# frozen_string_literal: true

require "extend/os/mac/cask/artifact/abstract_uninstall" if OS.mac?
require "extend/os/linux/cask/artifact/abstract_uninstall" if OS.linux?
