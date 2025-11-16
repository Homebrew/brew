# typed: strict
# frozen_string_literal: true

require "extend/os/mac/bundle/flatpak_dumper" if OS.mac?
require "extend/os/linux/bundle/flatpak_dumper" if OS.linux?
