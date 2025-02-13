# typed: strict
# frozen_string_literal: true

require "extend/os/mac/cask/artifact/symlinked" if OS.mac?
require "extend/os/linux/cask/artifact/symlinked" if OS.linux?
