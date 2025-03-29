# typed: strict
# frozen_string_literal: true

require "extend/os/mac/utils/bottles" if OS.mac?
require "extend/os/linux/utils/bottles" if OS.linux?
