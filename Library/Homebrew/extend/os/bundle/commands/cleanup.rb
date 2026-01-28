# typed: strict
# frozen_string_literal: true

require "extend/os/mac/bundle/commands/cleanup" if OS.mac?
require "extend/os/linux/bundle/commands/cleanup" if OS.linux?
