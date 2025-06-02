# frozen_string_literal: true

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

        next unless path = loc.path
        unless path.start_with?(rubygems_path, "<internal:")
          # Non-rubygems frames
          uplevel -= 1
        end
      end
      kw[:uplevel] = start
    end

    original_warn.bind(self).call(*messages, **kw)
  }
end
