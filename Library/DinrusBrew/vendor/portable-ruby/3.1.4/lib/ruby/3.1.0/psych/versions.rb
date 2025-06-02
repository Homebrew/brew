# frozen_string_literal: true

module Psych
  # The version of Psych you are using
  VERSION = '4.0.4'

  if RUBY_ENGINE == 'jruby'
    DEFAULT_SNAKEYAML_VERSION = '1.28'.freeze
  end
end
