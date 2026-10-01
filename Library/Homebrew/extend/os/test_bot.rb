# typed: strict
# frozen_string_literal: true

require "extend/os/linux/test_bot" if OS.linux?
require "extend/os/mac/test_bot" if OS.mac?
