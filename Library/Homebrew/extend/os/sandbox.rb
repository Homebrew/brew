# typed: strict
# frozen_string_literal: true

require "extend/os/#{OS.mac? ? "mac" : "linux"}/sandbox"
