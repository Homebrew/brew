# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    module Cask
      module Utils
        module Trash
          module ClassMethods
            sig {
              params(paths: ::Pathname, command: T.nilable(T.class_of(SystemCommand)))
                .returns([T::Array[String], T::Array[String]])
            }
            def trash(*paths, command: nil)
              freedesktop_trash(*paths)
            end
          end
        end
      end
    end
  end
end

Cask::Utils::Trash.singleton_class.prepend(OS::Linux::Cask::Utils::Trash::ClassMethods)
