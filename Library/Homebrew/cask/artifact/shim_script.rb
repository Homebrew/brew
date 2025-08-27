# typed: strict
# frozen_string_literal: true

require "cask/artifact/relocated"

module Cask
  module Artifact
    # Artifact corresponding to a `shim_script` stanza.
    #
    # Purpose: many casks currently create small wrapper scripts in preflight
    # blocks. This artifact standardizes that behavior.
    #
    # Usage examples in a cask:
    #   shim_script "App.app/Contents/MacOS/foo", target: "foo"
    #   shim_script "bin/tool", target: "tool", args: ["--flag"], env: { "FOO" => "bar" }
    #   shim_script "App.app/Contents/MacOS/foo", target: "foo" do |source|
    #     "#!/bin/sh\nexec \"#{source}\" --special \"$@\"\n"
    #   end
    #
    # By default the content will exec the resolved source with optional args
    # and preserved environment. A custom block can override the entire content.
    class ShimScript < Relocated
      VALID_KWARGS = T.let(Set.new([:target, :args, :env, :sudo, :content]).freeze, T::Set[Symbol])

      sig {
        params(
          cask:  Cask,
          args:  T.untyped,
          block: T.nilable(T.proc.params(arg0: T.any(String, Pathname)).returns(T.untyped)),
        ).returns(T.attached_class)
      }
      def self.from_args(cask, *args, &block)
        source_string, options = args
        raise CaskInvalidError.new(cask.token, "No source provided for Shim Script.") if source_string.blank?

        options ||= {}
        unless options.respond_to?(:keys)
          raise CaskInvalidError.new(cask.token, "Invalid options for Shim Script: #{options.inspect}")
        end

        unknown = options.keys - VALID_KWARGS.to_a
        raise CaskInvalidError.new(cask.token, "Unknown keys for shim_script: #{unknown.inspect}") if unknown.any?

        new(cask, source_string, **options, &block)
      end

      sig {
        params(
          cask:    Cask,
          source:  T.any(String, Pathname),
          target:  T.nilable(T.any(String, Pathname)),
          args:    T.nilable(T.any(String, T::Array[T.untyped])),
          env:     T.nilable(T::Hash[T.any(String, Symbol), T.untyped]),
          sudo:    T::Boolean,
          content: T.nilable(String),
          block:   T.nilable(T.proc.params(arg0: T.any(String, Pathname)).returns(T.untyped)),
        ).void
      }
      def initialize(cask, source, target: nil, args: nil, env: nil, sudo: false, content: nil, &block)
        @args = T.let(Array(args).compact.map(&:to_s), T::Array[String])
        @env = T.let(env ? env.to_h.transform_keys(&:to_s) : {}, T::Hash[String, T.untyped])
        @sudo = T.let(sudo, T::Boolean)
        @content_string = T.let(content, T.nilable(String))
        @content_block = T.let(block, T.nilable(T.proc.params(arg0: T.any(String, Pathname)).returns(T.untyped)))
        if target.nil?
          super(cask, source)
        else
          super(cask, source, target: target)
        end
        # Declare ivars set in super for strict typing in this subclass
        @source_string = T.let(@source_string, String)
        @target_string = T.let(@target_string, String)
      end

      sig {
        params(
          command: T.untyped,
          force:   T::Boolean,
          adopt:   T::Boolean,
          _kwargs: T.untyped,
        ).void
      }
      def install_phase(command: nil, force: false, adopt: false, **_kwargs)
        write_shim(command, force: force, adopt: adopt)
      end

      sig { params(command: T.untyped, _kwargs: T.untyped).void }
      def uninstall_phase(command: nil, **_kwargs)
        Utils.gain_permissions_remove(target, command:) if target.exist?
      end

      private

      sig { params(target: T.any(String, Pathname)).returns(Pathname) }
      def resolve_target(target)
        target = Pathname(target)
        if target.relative?
          return target.expand_path if target.descend.first.to_s == "~"

          return config.binarydir/target
        end

        target
      end

      sig { returns(String) }
      def default_content
        # Resolve source: prefer the installed app path if wrapping an app bundle
        src = begin
          src_str = to_a.first.to_s
          if Pathname(src_str).absolute? || src_str.start_with?("~")
            staged_path_join_executable(src_str)
          elsif src_str.include?(".app/")
            # Target inside an app bundle; use the installed appdir location
            (Pathname(config.appdir)/src_str).to_s
          else
            staged_path_join_executable(src_str).to_s
          end
        end
        env_exports = @env.map { |k, v| "export #{k}=#{v.to_s.shellescape}" }.join("\n")
        arg_str = @args.map { |x| x.to_s.shellescape }.join(" ")
        shebang = "#!/bin/sh"
        body = []
        body << "set -e"
        body << env_exports unless env_exports.empty?
        exec_prefix = @sudo ? "exec sudo -- " : "exec "
        body << %Q(#{exec_prefix}"#{src}" #{arg_str} "$@")
        "#{([shebang] + body).join("\n")}\n"
      end

      sig {
        params(
          command: T.untyped,
          force:   T::Boolean,
          adopt:   T::Boolean,
        ).void
      }
      def write_shim(command, force: false, adopt: false)
        target_path = target
        dir = target_path.dirname
        dir.mkpath unless dir.exist?

        if target_path.exist?
          message = "It seems there is already a Shim Script at '#{target_path}'"
          needs_overwrite = !(force || adopt)
          raise CaskError, "#{message}." if needs_overwrite

          opoo "#{message}; overwriting."
          Utils.gain_permissions_remove(target_path, command:)
        end

        content = if @content_string
          @content_string
        elsif @content_block
          # Allow the block to generate custom content. Pass the resolved source path.
          @content_block.call(staged_path_join_executable(source)).to_s
        else
          default_content
        end

        ohai "Creating shim script '#{target_path}'"
        target_path.atomic_write(content)

        if target_path.writable?
          FileUtils.chmod("+x", target_path)
        else
          command.run!("/bin/chmod", args: ["+x", target_path], sudo: true)
        end
      end

      public

      sig { returns(T::Array[T.untyped]) }
      def to_args
        src = to_a.first

        opts = {}
        opts[:target] = @target_string unless @target_string.empty?
        opts[:args] = @args if @args.any?
        opts[:env] = @env if @env.any?
        opts[:sudo] = true if @sudo
        # If explicit content is provided or a block exists, include a deterministic content string
        # so the API can round-trip this artifact without blocks.
        if @content_string
          opts[:content] = @content_string
        elsif @content_block
          # Use the original source string for API content to keep it stable pre-install.
          opts[:content] = @content_block.call(src).to_s
        end

        [src, (opts unless opts.empty?)].compact
      end
    end
  end
end
