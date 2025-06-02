# frozen_string_literal: true

return if ENV['RUBY_DEBUG_ENABLE'] == '0'
return if defined?(::DEBUGGER__)

# Put the following line in your login script (e.g. ~/.bash_profile) with modified path:
#
#   export RUBYOPT="-r /path/to/debug/prelude $(RUBYOPT)"
#
module Kernel
  def debugger(*a, up_level: 0, **kw)
    begin
      require_relative 'version'
      cur_version = ::DEBUGGER__::VERSION
      require_relative 'frame_info'

      if !defined?(::DEBUGGER__::SO_VERSION) || ::DEBUGGER__::VERSION != ::DEBUGGER__::SO_VERSION
        ::Object.send(:remove_const, :DEBUGGER__)
        raise LoadError
      end
      require_relative 'session'
      up_level += 1
    rescue LoadError
      $LOADED_FEATURES.delete_if{|e|
        e.start_with?(__dir__) || e.end_with?('debug/debug.so')
      }
      require 'debug/session'
      require 'debug/version'
      ::DEBUGGER__.info "Can not activate debug #{cur_version} specified by debug/prelude.rb. Activate debug #{DEBUGGER__::VERSION} instead."
      up_level += 1
    end

    ::DEBUGGER__::start no_sigint_hook: true, nonstop: true

    begin
      debugger(*a, up_level: up_level, **kw)
      self
    rescue ArgumentError # for 1.2.4 and earlier
      debugger(*a, **kw)
      self
    end
  end

  alias bb debugger if ENV['RUBY_DEBUG_BB']
end

class Binding
  alias break debugger
  alias b debugger
end
