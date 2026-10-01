# typed: strict
# frozen_string_literal: true

require "extend/os/linux/cask/artifact/moved" if OS.linux?
require "extend/os/mac/cask/artifact/moved" if OS.mac?
