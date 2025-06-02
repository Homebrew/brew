# frozen_string_literal: false
require_relative 'drb'
require 'monitor'

module DRb

  # To use WeakIdConv:
  #
  #  DRb.start_service(nil, nil, {:idconv => DRb::WeakIdConv.new})

  class WeakIdConv < DRbIdConv
    class WeakSet
      include MonitorMixin
      def initialize
        super()
        @immutable = {}
        @map = ObjectSpace::WeakMap.new
      end

      def add(obj)
        synchronize do
          begin
            @map[obj] = self
          rescue ArgumentError
            @immutable[obj.__id__] = obj
          end
          return obj.__id__
        end
      end

      def fetch(ref)
        synchronize do
          @immutable.fetch(ref) {
            @map.each { |key, _|
              return key if key.__id__ == ref
            }
            raise RangeError.new("invalid reference")
          }
        end
      end
    end

    def initialize()
      super()
      @weak_set = WeakSet.new
    end

    def to_obj(ref) # :nodoc:
      return super if ref.nil?
      @weak_set.fetch(ref)
    end

    def to_id(obj) # :nodoc:
      return @weak_set.add(obj)
    end
  end
end

# DRb.install_id_conv(WeakIdConv.new)
