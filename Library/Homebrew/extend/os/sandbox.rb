# typed: strict
# frozen_string_literal: true

require "extend/os/mac/sandbox" if OS.mac?
require "extend/os/linux/sandbox" if OS.linux?
