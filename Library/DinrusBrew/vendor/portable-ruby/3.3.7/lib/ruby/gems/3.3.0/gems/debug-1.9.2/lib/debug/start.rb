# frozen_string_literal: true

require_relative 'session'
return unless defined?(DEBUGGER__)
DEBUGGER__.start no_sigint_hook: false
