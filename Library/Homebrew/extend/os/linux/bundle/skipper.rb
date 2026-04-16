# typed: strict
# frozen_string_literal: true

require "cask/cask_loader"
module OS
  module Linux
    module Bundle
      module Skipper
        module ClassMethods
          sig { params(entry: Homebrew::Bundle::Dsl::Entry).returns(T::Boolean) }
          def requires_macos?(entry)
            case entry.type
            when :mas
              true
            when :cask
              !::Cask::CaskLoader.load(entry.name).supports_linux?
            else
              false
            end
          rescue ::Cask::CaskError
            # If the cask can't be loaded, it may be from a tap that hasn't been
            # tapped yet. Don't assume macOS-only in that case — let the normal
            # install flow handle it after the tap is processed.
            full_name = T.cast(entry.options[:full_name], T.nilable(String))
            return false if full_name&.include?("/")

            true
          end

          sig { params(entry: Homebrew::Bundle::Dsl::Entry, silent: T::Boolean).returns(T::Boolean) }
          def skip?(entry, silent: false)
            return super unless requires_macos?(entry)

            $stdout.puts Formatter.warning("Skipping #{entry.type} #{entry.name} (requires macOS)") unless silent
            true
          end
        end
      end
    end
  end
end

Homebrew::Bundle::Skipper.singleton_class.prepend(OS::Linux::Bundle::Skipper::ClassMethods)
