# typed: strict
# frozen_string_literal: true

require "extend/os/mac/cask/utils/trash" if OS.mac?
require "extend/os/linux/cask/utils/trash" if OS.linux?
