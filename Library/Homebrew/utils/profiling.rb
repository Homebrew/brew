# typed: strict
# frozen_string_literal: true

module Utils
  module Profiling
    @injected_modules = T.let({}, T::Hash[T::Module[T.anything], T::Array[Symbol]])

    # Uses $times to share timing data between wrapped methods and the at_exit reporter.
    # rubocop:disable Style/GlobalVars
    sig { params(the_module: T::Module[T.anything], pattern: Regexp).void }
    def self.inject_stats!(the_module, pattern)
      @injected_modules[the_module] ||= []
      injected_methods = @injected_modules.fetch(the_module)
      wrapper = Module.new
      the_module.instance_methods.grep(pattern).each do |name|
        next if injected_methods.include? name

        injected_methods << name
        wrapper.define_method(name) do |*args, &block|
          require "time"

          time = Time.now

          begin
            super(*args, &block)
          ensure
            $times[name] ||= 0
            $times[name] += Time.now - time
          end
        end
      end
      the_module.prepend(wrapper)

      return unless $times.nil?

      $times = {}
      Kernel.at_exit do
        col_width = [$times.keys.map(&:size).max.to_i + 2, 15].max
        $times.sort_by { |_method, time| time }.each do |method, time|
          $stdout.puts Kernel.format("%<method>-#{col_width}s %<time>0.4f sec", method: "#{method}:", time:)
        end
      end
    end
    # rubocop:enable Style/GlobalVars
  end
end
