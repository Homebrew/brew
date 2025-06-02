# frozen_string_literal: true

module Psych
  # The version of Psych you are using
  VERSION = '5.1.2'

  if RUBY_ENGINE == 'jruby'
    DEFAULT_SNAKEYAML_VERSION = '2.7'.freeze
  end
end
