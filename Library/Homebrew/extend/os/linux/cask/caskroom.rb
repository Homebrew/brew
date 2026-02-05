# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    module Cask
      module Caskroom
        module ClassMethods
          sig { params(path: ::Pathname, _sudo: T::Boolean).void }
          def chgrp_path(path, _sudo)
            SystemCommand.run("chgrp", args: ["root", path], sudo: true)
          end
        end
      end
    end
  end
end

Cask::Caskroom.singleton_class.prepend(OS::Linux::Cask::Caskroom::ClassMethods)
