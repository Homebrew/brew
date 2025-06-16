# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    module DevCmd
      module UpdateTest
        private

        sig { returns(String) }
        def git_tags
          super.presence || Utils.popen_read("git tag --list | sort -rV")
        end
      end
    end
  end
end

Homebrew::DevCmd::UpdateTest.prepend(OS::Linux::DevCmd::UpdateTest)
