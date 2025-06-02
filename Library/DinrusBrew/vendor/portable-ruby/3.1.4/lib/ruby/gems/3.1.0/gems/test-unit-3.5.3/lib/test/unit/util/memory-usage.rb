module Test
  module Unit
    module Util
      class MemoryUsage
        attr_reader :virtual
        attr_reader :physical
        def initialize
          @virtual = nil
          @physical = nil
          collect_data
        end

        def collected?
          return false if @virtual.nil?
          return false if @physical.nil?
          true
        end

        private
        def collect_data
          collect_data_proc
        end

        def collect_data_proc
          status_file = "/proc/self/status"
          return false unless File.exist?(status_file)

          data = File.binread(status_file)
          data.each_line do |line|
            case line
            when /\AVm(Size|RSS):\s*(\d+)\s*kB/
              name = $1
              value = Integer($2, 10) * 1024
              case name
              when "Size"
                @virtual = value
              when "RSS"
                @physical = value
              end
            end
          end
          collected?
        end
      end
    end
  end
end
