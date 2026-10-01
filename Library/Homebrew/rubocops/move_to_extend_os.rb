# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Homebrew
      # This cop ensures that platform specific code ends up in `extend/os`, and
      # that `extend/os` doesn't contain incorrect or redundant OS checks.
      class MoveToExtendOS < Base
        NON_EXTEND_OS_MSG = "Move `OS.linux?` and `OS.mac?` calls to `extend/os`."

        def_node_matcher :os_mac?, <<~PATTERN
          (send (const nil? :OS) :mac?)
        PATTERN

        def_node_matcher :os_linux?, <<~PATTERN
          (send (const nil? :OS) :linux?)
        PATTERN

        sig { params(extend_os: String, os_method: String).returns(String) }
        def extend_offense_message(extend_os, os_method)
          "Don't use `OS.#{os_method}?` in `extend/os/#{extend_os}`, it is " \
            "always `#{(extend_os == os_method) ? "true" : "false"}`."
        end

        sig { params(node: RuboCop::AST::Node).void }
        def on_send(node)
          file_path = processed_source.file_path
          # The OS loader, requirements and tests need direct host checks; this
          # cop is for portable production code that should live under `extend/os`.
          return if file_path.match?(%r{(?:\A|/)Library/Homebrew/(?:requirements|test)/}) ||
                    file_path.match?(%r{(?:\A|/)Library/Homebrew/os\.rb\z})

          if file_path.include?("extend/os/mac/")
            add_offense(node, message: extend_offense_message("mac", "mac")) if os_mac?(node)
            add_offense(node, message: extend_offense_message("mac", "linux")) if os_linux?(node)
          elsif file_path.include?("extend/os/linux/")
            add_offense(node, message: extend_offense_message("linux", "mac")) if os_mac?(node)
            add_offense(node, message: extend_offense_message("linux", "linux")) if os_linux?(node)
          elsif !file_path.include?("extend/os/") && (os_mac?(node) || os_linux?(node))
            add_offense(node, message: NON_EXTEND_OS_MSG)
          end
        end
      end
    end
  end
end
