# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module Cmd
      module Info
        private

        sig { params(requirement: Requirement).returns(T::Boolean) }
        def requirement_for_other_os?(requirement)
          requirement.instance_of?(::LinuxRequirement)
        end
      end
    end
  end
end

Homebrew::Cmd::Info.singleton_class.prepend(OS::Mac::Cmd::Info)
