# typed: strict
# frozen_string_literal: true

require "extend/os/linux/dev-cmd/bottle" if OS.linux?
require "extend/os/mac/dev-cmd/bottle" if OS.mac?
