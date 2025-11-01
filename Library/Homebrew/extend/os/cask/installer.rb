# typed: strict
# frozen_string_literal: true

require "extend/os/linux/cask/installer" if OS.linux?
require "extend/os/mac/cask/installer" if OS.mac?
