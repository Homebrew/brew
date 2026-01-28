# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module Tap
      module ClassMethods
        sig { returns(T::Array[::Tap]) }
        def core_taps
          [CoreTap.instance, CoreCaskTap.instance].freeze
        end
      end
    end
  end
end

Tap.singleton_class.prepend(OS::Mac::Tap::ClassMethods)
