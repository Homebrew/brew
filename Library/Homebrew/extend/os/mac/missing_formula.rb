# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module MissingFormula
      module ClassMethods
        sig { params(name: String).returns(T.nilable(String)) }
        def disallowed_reason(name)
          case name.downcase
          when "xcode"
            <<~EOS
              Xcode can be installed from the App Store.
            EOS
          else
            super
          end
        end
      end
    end
  end
end

Homebrew::MissingFormula.singleton_class.prepend(OS::Mac::MissingFormula::ClassMethods)
