# typed: strict
# frozen_string_literal: true

require "cask/cask_loader"
require "cask/installer"

module OS
  module Linux
    module Bundle
      module Skipper
        module ClassMethods
          sig { params(entry: Homebrew::Bundle::Dsl::Entry).returns(T::Boolean) }
          def macos_only_entry?(entry)
            entry.type == :mas
          end

          sig { params(entry: Homebrew::Bundle::Dsl::Entry).returns(T::Boolean) }
          def macos_only_cask?(entry)
            return false if entry.type != :cask

            cask = ::Cask::CaskLoader.load(entry.name)
            installer = ::Cask::Installer.new(cask)
            installer.check_stanza_os_requirements

            false
          rescue ::Cask::CaskError
            true
          end

          sig { params(entry: Homebrew::Bundle::Dsl::Entry, silent: T::Boolean).returns(T::Boolean) }
          def skip?(entry, silent: false)
            if macos_only_entry?(entry) || macos_only_cask?(entry)
              unless silent
                $stdout.puts Formatter.warning "Skipping #{entry.type} #{entry.name} (unsupported on Linux)"
              end

              true
            else
              super(entry)
            end
          end
        end
      end
    end
  end
end

Homebrew::Bundle::Skipper.singleton_class.prepend(OS::Linux::Bundle::Skipper::ClassMethods)
