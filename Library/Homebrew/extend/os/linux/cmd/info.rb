# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    module Cmd
      module Info
        private

        sig { params(requirement: Requirement).returns(T::Boolean) }
        def requirement_for_other_os?(requirement)
          requirement.instance_of?(::MacOSRequirement)
        end
      end
    end
  end
end

Homebrew::Cmd::Info.singleton_class.prepend(OS::Linux::Cmd::Info)
