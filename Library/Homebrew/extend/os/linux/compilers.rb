# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    module CompilerSelector
      module ClassMethods
        extend T::Helpers

        requires_ancestor { T.class_of(::CompilerSelector) }

        sig { returns(String) }
        def preferred_gcc
          OS::LINUX_PREFERRED_GCC_COMPILER_FORMULA
        end
      end
    end
  end
end

CompilerSelector.singleton_class.prepend(OS::Linux::CompilerSelector::ClassMethods)
