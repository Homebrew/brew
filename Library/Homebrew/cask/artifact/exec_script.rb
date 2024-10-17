# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "cask/artifact/binary"

module Cask
  module Artifact
    # Artifact corresponding to the `exec_script` stanza.
    class ExecScript < Binary
      DEFAULT_ARGS = ["$@"].freeze

      def self.from_args(cask, source, **args)
        new(cask, source, **args)
      end

      sig {
        params(
          cask:       Cask,
          source:     T.any(String, Pathname),
          # File name for installed script. The default is the basename of `source`
          target:     T.nilable(String),
          # File name for wrapper script. The default is `#{target}.wrapper.sh`
          wrapper:    T.nilable(String),
          # Arguments added to exec script for source command
          args:       T.nilable(T::Array[T.any(String, Pathname)]),
          # Set to `false` to disable adding double quotes around each argument in `args`
          quote_args: T::Boolean,
          # The shell for shebang. The default is `/bin/bash`
          shell:      String,
          # A location to send standard error. Nothing by default. Can be set to `/dev/null` or a file
          stderr:     T.nilable(T.any(String, Pathname)),
          # Directory to change to before running exec command
          chdir:      T.nilable(T.any(String, Pathname)),
        ).void
      }
      def initialize(cask, source, target: nil, wrapper: nil, args: nil,
                     quote_args: true, shell: "/bin/bash", stderr: nil, chdir: nil)
        raise CaskInvalidError, "`wrapper` must be a file name instead of a path" if wrapper&.include?("/")
        raise CaskInvalidError, "`target` must be a file name instead of a path" if target&.include?("/")

        @command = cask.staged_path.join(source)
        @wrapper = cask.staged_path.join(wrapper || "#{target || @command.basename}.wrapper.sh")
        @args = args || DEFAULT_ARGS
        @quote_args = quote_args
        @shell = shell
        @stderr = stderr
        @chdir = chdir

        super(cask, @wrapper, target: target || @command.basename)
      end

      def install_phase(**options)
        require "utils/shell"

        chdir = "cd #{::Utils::Shell.sh_quote(@chdir.to_s)} && " if @chdir
        args = (@quote ? @args.map { |arg| "\"#{arg}\"" } : @args).join(" ")
        stderr = " 2>#{::Utils::Shell.sh_quote(@stderr.to_s)}" if @stderr

        @wrapper.write <<~EOS
          #!#{@shell}
          #{chdir}exec "#{@command}" #{args}#{stderr}
        EOS
        super
      end
    end
  end
end
