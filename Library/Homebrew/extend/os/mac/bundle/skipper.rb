# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module Bundle
      module Skipper
        module ClassMethods
          sig { params(entry: Homebrew::Bundle::Dsl::Entry).returns(T::Boolean) }
          def linux_only_entry?(entry)
            entry.type == :flatpak
          end

          sig { params(entry: Homebrew::Bundle::Dsl::Entry, silent: T::Boolean).returns(T::Boolean) }
          def skip?(entry, silent: false)
            if linux_only_entry?(entry)
              unless silent
                Kernel.puts Formatter.warning "Skipping #{entry.type} #{entry.name} (unsupported on macOS)"
              end
              true
            else
              super
            end
          end
        end
      end
    end
  end
end

Homebrew::Bundle::Skipper.singleton_class.prepend(OS::Mac::Bundle::Skipper::ClassMethods)
