# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    module Search
      module ClassMethods
        sig { params(cask: ::Cask::Cask).returns(T::Boolean) }
        def ignore_cask?(cask)
          !cask.supports_linux?
        end
      end
    end
  end
end

Homebrew::Search.singleton_class.prepend(OS::Linux::Search::ClassMethods)
