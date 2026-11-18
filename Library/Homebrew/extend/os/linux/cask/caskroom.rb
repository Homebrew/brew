# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    module Cask
      module Caskroom
        module ClassMethods
          sig { returns(T.nilable(String)) }
          def shared_caskroom_group
            nil
          end

          # Unlike macOS (which uses the `admin` group), Homebrew on Linux is run
          # in a variety of distributions, so use the current user's primary group
          # as the group of the `Caskroom` directory.
          # This avoids a `sudo` prompt to `chgrp` the directory after creation.
          sig { returns(String) }
          def expected_caskroom_group
            return @expected_caskroom_group if @expected_caskroom_group

            expected_caskroom_group = begin
              Etc.getgrgid(Process.egid)&.name || "root"
            rescue ArgumentError
              "root"
            end
            @expected_caskroom_group = T.let(expected_caskroom_group, T.nilable(String))
            expected_caskroom_group
          end
        end
      end
    end
  end
end

Cask::Caskroom.singleton_class.prepend(OS::Linux::Cask::Caskroom::ClassMethods)
