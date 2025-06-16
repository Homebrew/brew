# typed: strict
# frozen_string_literal: true

# This file should be the first `require` in all entrypoints of `brew`.
# Bootsnap should be loaded as early as possible.

require_relative "standalone/init"
require_relative "startup/bootsnap"
require_relative "startup/ruby_path"
require "startup/config"
require_relative "standalone/sorbet"
