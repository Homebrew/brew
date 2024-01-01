# typed: strict
# frozen_string_literal: true

# This file should be the first `require` in all entrypoints of `brew`.

require_relative "standalone/init"
require_relative "startup/ruby_path"
require "startup/config"
require_relative "startup/bootsnap"
require_relative "standalone/sorbet"
