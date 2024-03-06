# typed: true
# frozen_string_literal: true

module RuboCop
  module Cop
    module Homebrew
      # This cop ensures that platform specific code ends up in `extend/os`.
      class MoveToExtendOS < Base
        MSG = "Move `OS.linux?` and `OS.mac?` calls to `extend/os`."

        def_node_matcher :os_check?, <<~PATTERN
          (send (const nil? :OS) {:mac? | :linux?})
        PATTERN

        def on_send(node)
          return unless os_check?(node)

          add_offense(node)
        end
      end
    end
  end
end
