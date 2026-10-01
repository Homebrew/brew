# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module Language
      module Java
        module ClassMethods
          extend T::Helpers

          requires_ancestor { T.class_of(::Language::Java) }

          sig { params(version: T.nilable(String)).returns(T.nilable(::Pathname)) }
          def java_home(version = nil)
            openjdk = find_openjdk_formula(version)
            return unless openjdk

            openjdk.opt_libexec/"openjdk.jdk/Contents/Home"
          end
        end
      end
    end
  end
end

Language::Java.singleton_class.prepend(OS::Mac::Language::Java::ClassMethods)
