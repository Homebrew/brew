# typed: strict
# frozen_string_literal: true

require "extend/os/mac/bundle/flatpak_remote_checker" if OS.mac?
require "extend/os/linux/bundle/flatpak_remote_checker" if OS.linux?
