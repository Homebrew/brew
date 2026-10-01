# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    module BottleSpecification
      sig { params(tag: Utils::Bottles::Tag, tab: T.nilable(Tab)).returns(T::Boolean) }
      def skip_relocation?(tag: Utils::Bottles.tag, tab: nil)
        # Homebrew versions prior to 5.1.15 generated incorrect :any_skip_relocation
        !tab.nil? && tab.parsed_homebrew_version >= "5.1.15" && super
      end
    end
  end
end

BottleSpecification.prepend(OS::Linux::BottleSpecification)
