# typed: strict
# frozen_string_literal: true

require "extend/os/mac/bundle/bundle" if OS.mac?
require "extend/os/linux/bundle/bundle" if OS.linux?
