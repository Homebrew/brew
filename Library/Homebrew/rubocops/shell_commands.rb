# typed: true
# frozen_string_literal: true

require "active_support/core_ext/array/access"
require "rubocops/shared/helper_functions"
require "shellwords"

module RuboCop
  module Cop
    module Homebrew
      # https://github.com/ruby/ruby/blob/v2_6_3/process.c#L2430-L2460
      SHELL_BUILTINS = %w[
        !
        .
        :
        break
        case
        continue
        do
        done
        elif
        else
        esac
        eval
        exec
        exit
        export
        fi
        for
        if
        in
        readonly
        return
        set
        shift
        then
        times
        trap
        unset
        until
        while
      ].freeze

      # https://github.com/ruby/ruby/blob/v2_6_3/process.c#L2495
      SHELL_METACHARACTERS = %W[* ? { } [ ] < > ( ) ~ & | \\ $ ; ' ` " \n #].freeze

      # This cop makes sure that shell command arguments are separated.
      #
      # @api private
      class ShellCommands < Base
        include HelperFunctions
        extend AutoCorrector

        MSG = "Separate `%<method>s` commands into `%<good_args>s`"

        TARGET_METHODS = [
          [nil, :system],
          [nil, :safe_system],
          [nil, :quiet_system],
          [:Utils, :popen_read],
          [:Utils, :safe_popen_read],
          [:Utils, :popen_write],
          [:Utils, :safe_popen_write],
        ].freeze
        RESTRICT_ON_SEND = TARGET_METHODS.map(&:second).uniq.freeze

        def on_send(node)
          TARGET_METHODS.each do |target_class, target_method|
            next if node.method_name != target_method

            target_receivers = if target_class.nil?
              [nil, s(:const, nil, :Kernel), s(:const, nil, :Homebrew)]
            else
              [s(:const, nil, target_class)]
            end
            next unless target_receivers.include?(node.receiver)

            first_arg = node.arguments.first
            arg_count = node.arguments.count
            if first_arg&.hash_type? # popen methods allow env hash
              first_arg = node.arguments.second
              arg_count -= 1
            end
            next if first_arg.nil? || arg_count >= 2

            first_arg_str = string_content(first_arg)
            stripped_first_arg_str = string_content(first_arg, strip_dynamic: true)

            split_args = first_arg_str.shellsplit
            next if split_args.count <= 1

            # Only separate when no shell metacharacters are present
            command = split_args.first
            next if SHELL_BUILTINS.any?(command)
            next if command&.include?("=")
            next if SHELL_METACHARACTERS.any? { |meta| stripped_first_arg_str.include?(meta) }

            good_args = split_args.map { |arg| "\"#{arg}\"" }.join(", ")
            method_string = if target_class
              "#{target_class}.#{target_method}"
            else
              target_method.to_s
            end
            add_offense(first_arg, message: format(MSG, method: method_string, good_args: good_args)) do |corrector|
              corrector.replace(first_arg.source_range, good_args)
            end
          end
        end
      end

      # This cop disallows shell metacharacters in `exec` calls.
      #
      # @api private
      class ExecShellMetacharacters < Base
        include HelperFunctions

        MSG = "Don't use shell metacharacters in `exec`. " \
              "Implement the logic in Ruby instead, using methods like `$stdout.reopen`."

        RESTRICT_ON_SEND = [:exec].freeze

        def on_send(node)
          return if node.receiver.present? && node.receiver != s(:const, nil, :Kernel)
          return if node.arguments.count != 1

          stripped_arg_str = string_content(node.arguments.first, strip_dynamic: true)
          command = string_content(node.arguments.first).shellsplit.first

          return if SHELL_BUILTINS.none?(command) &&
                    !command&.include?("=") &&
                    SHELL_METACHARACTERS.none? { |meta| stripped_arg_str.include?(meta) }

          add_offense(node.arguments.first, message: MSG)
        end
      end
    end
  end
end
