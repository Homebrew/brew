# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module Sandbox
      module ClassMethods
        extend T::Helpers

        requires_ancestor { T.class_of(::Sandbox) }

        sig { returns(T::Boolean) }
        def available?
          File.executable?(::Sandbox::SANDBOX_EXEC)
        end
      end
    end
  end
end

Sandbox.singleton_class.prepend(OS::Mac::Sandbox::ClassMethods)
