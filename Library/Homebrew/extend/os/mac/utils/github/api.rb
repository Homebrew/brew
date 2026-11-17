# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module GitHubAPI
      module ClassMethods
        sig { returns(T::Boolean) }
        def keychain_available? = true
      end
    end
  end
end

GitHub::API.singleton_class.prepend(OS::Mac::GitHubAPI::ClassMethods)
