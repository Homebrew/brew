# frozen_string_literal: true

# `uplevel` keyword argument of Kernel#warn is available since ruby 2.5.
if RUBY_VERSION >= "2.5" && !Gem::KERNEL_WARN_IGNORES_INTERNAL_ENTRIES

  module Kernel
    rubygems_path = "#{__dir__}/" # Frames to be skipped start with this path.

    original_warn = instance_method(:warn)

    remove_method :warn

    class << self
      remove_method :warn
    end

    module_function define_method(:warn) {|*messages, **kw|
      unless uplevel = kw[:uplevel]
        if Gem.java_platform? && RUBY_VERSION < "3.1"
          return original_warn.bind(self).call(*messages)
        else
          return original_warn.bind(self).call(*messages, **kw)
        end
      end

      # Ensure `uplevel` fits a `long`
      uplevel, = [uplevel].pack("l!").unpack("l!")

      if uplevel >= 0
        start = 0
        while uplevel >= 0
          loc, = caller_locations(start, 1)
          unless loc
            # No more backtrace
            start += uplevel
            break
          end

          start += 1

          if path = loc.path
            unless path.start_with?(rubygems_path) || path.start_with?("<internal:")
              # Non-rubygems frames
              uplevel -= 1
            end
          end
        end
        kw[:uplevel] = start
      end

      original_warn.bind(self).call(*messages, **kw)
    }
  end
end
