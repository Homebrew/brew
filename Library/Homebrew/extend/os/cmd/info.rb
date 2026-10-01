# typed: strict
# frozen_string_literal: true

require "extend/os/linux/cmd/info" if OS.linux?
require "extend/os/mac/cmd/info" if OS.mac?
