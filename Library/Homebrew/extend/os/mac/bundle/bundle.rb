# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module Bundle
      module ClassMethods
      end
    end
  end
end

Homebrew::Bundle.singleton_class.prepend(OS::Mac::Bundle::ClassMethods)
