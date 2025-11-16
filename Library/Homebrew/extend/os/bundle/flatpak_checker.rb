# typed: strict
# frozen_string_literal: true

require "extend/os/mac/bundle/flatpak_checker" if OS.mac?
require "extend/os/linux/bundle/flatpak_checker" if OS.linux?
