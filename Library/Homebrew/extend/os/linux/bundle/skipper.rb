# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module OS
  module Linux
    module Bundle
      module Skipper
        module ClassMethods
          def macos_only_entry?(entry)
            [:cask, :mas].include?(entry.type)
          end

          def macos_only_tap?(entry)
            entry.type == :tap && entry.name == "homebrew/cask"
          end

          def skip?(entry, silent: false)
            if macos_only_entry?(entry) || macos_only_tap?(entry)
              ::Kernel.puts Formatter.warning "Skipping #{entry.type} #{entry.name} (on Linux)" unless silent
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
