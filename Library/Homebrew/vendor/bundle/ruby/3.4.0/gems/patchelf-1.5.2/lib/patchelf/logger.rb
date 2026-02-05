# frozen_string_literal: true

require 'logger'

require 'patchelf/helper'

module PatchELF
  # A logger for internal usage.
  module Logger
    module_function

    @logger = ::Logger.new($stderr).tap do |log|
      log.formatter = proc do |severity, _datetime, _progname, msg|
        "[#{PatchELF::Helper.colorize(severity, severity.downcase.to_sym)}] #{msg}\n"
      end
    end

    %i[debug info warn error level=].each do |sym|
      define_method(sym) do |msg|
        @logger.__send__(sym, msg)
        nil
      end
    end
  end
end
