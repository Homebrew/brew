# typed: strict
# frozen_string_literal: true

require "extend/os/mac/bundle/skipper" if OS.mac?
require "extend/os/linux/bundle/skipper" if OS.linux?
