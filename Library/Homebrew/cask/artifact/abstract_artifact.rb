# typed: strict
# frozen_string_literal: true

require "extend/object/deep_dup"
require "utils/output"

module Cask
  module Artifact
    # Abstract superclass for all artifacts.
    class AbstractArtifact
      extend T::Helpers
      extend ::Utils::Output::Mixin

      abstract!

      include Comparable
      include ::Utils::Output::Mixin

      # T.anything or the union of all possible argument types would be better choice, but it's convenient to be
      # able to invoke `.inspect`, `.to_s`, etc. without the overhead of type guards.
      DirectivesType = T.type_alias { Object }

      sig { overridable.returns(String) }
      def self.english_name
        @english_name ||= T.let(T.must(name).sub(/^.*:/, "").gsub(/(.)([A-Z])/, '\1 \2'), T.nilable(String))
      end

      sig { returns(String) }
      def self.english_article
        @english_article ||= T.let(/^[aeiou]/i.match?(english_name) ? "an" : "a", T.nilable(String))
      end

      sig { overridable.returns(Symbol) }
      def self.dsl_key
        @dsl_key ||= T.let(T.must(name).sub(/^.*:/, "").gsub(/(.)([A-Z])/, '\1_\2').downcase.to_sym,
                           T.nilable(Symbol))
      end

      sig { overridable.returns(Symbol) }
      def self.dirmethod
        @dirmethod ||= T.let(:"#{dsl_key}dir", T.nilable(Symbol))
      end

      sig { abstract.returns(String) }
      def summarize; end

      sig { params(path: T.any(String, Pathname)).returns(Pathname) }
      def staged_path_join_executable(path)
        path = Pathname(path)
        path = path.expand_path if path.to_s.start_with?("~")

        absolute_path = if path.absolute?
          path
        else
          cask.staged_path.join(path)
        end

        FileUtils.chmod "+x", absolute_path if absolute_path.exist? && !absolute_path.executable?

        if absolute_path.exist?
          absolute_path
        else
          path
        end
      end

      sig { returns(T::Hash[T.class_of(AbstractArtifact), Integer]) }
      def sort_order
        @sort_order ||= T.let(
          [
            PreflightBlock,
            # The `uninstall` stanza should be run first, as it may
            # depend on other artifacts still being installed.
            Uninstall,
            Installer,
            # `pkg` should be run before `binary`, so
            # targets are created prior to linking.
            # `pkg` should be run before `app`, since an `app` could
            # contain a nested installer (e.g. `wireshark`).
            Pkg,
            [
              App,
              Suite,
              Artifact,
              Colorpicker,
              Prefpane,
              Qlplugin,
              Mdimporter,
              Dictionary,
              Font,
              Service,
              InputMethod,
              InternetPlugin,
              KeyboardLayout,
              AudioUnitPlugin,
              VstPlugin,
              Vst3Plugin,
              ScreenSaver,
            ],
            Binary,
            Manpage,
            PostflightBlock,
            Zap,
          ].each_with_index.flat_map { |classes, i| Array(classes).map { |c| [c, i] } }.to_h,
          T.nilable(T::Hash[T.class_of(AbstractArtifact), Integer]),
        )
      end

      sig { override.params(other: BasicObject).returns(T.nilable(Integer)) }
      def <=>(other)
        case other
        when AbstractArtifact
          return 0 if instance_of?(other.class)

          (sort_order[self.class] <=> sort_order[other.class]).to_i
        end
      end

      # TODO: this sort of logic would make more sense in dsl.rb, or a
      #       constructor called from dsl.rb, so long as that isn't slow.
      sig {
        params(
          arguments:          DirectivesType,
          stanza:             T.any(String, Symbol),
          default_arguments:  T::Hash[Symbol, T.anything],
          override_arguments: T::Hash[Symbol, T.anything],
          key:                T.nilable(Symbol),
        ).returns([T.nilable(String), T::Hash[Symbol, T.untyped]])
      }
      def self.read_script_arguments(arguments, stanza, default_arguments = {}, override_arguments = {}, key = nil)
        # TODO: when stanza names are harmonized with class names,
        #       stanza may not be needed as an explicit argument
        description = key ? "#{stanza} #{key.inspect}" : stanza.to_s

        arguments = case arguments
        when String then { executable: arguments } # backward-compatible string value
        when Hash then arguments.dup # Avoid mutating the original argument
        else odie "Unsupported arguments type #{arguments.class}"
        end

        # key sanity
        permitted_keys = [:args, :input, :executable, :must_succeed, :sudo, :print_stdout, :print_stderr]
        unknown_keys = arguments.keys - permitted_keys
        unless unknown_keys.empty?
          opoo "Unknown arguments to #{description} -- " \
               "#{unknown_keys.inspect} (ignored). Running " \
               "`brew update; brew cleanup` will likely fix it."
        end
        arguments.select! { |k| permitted_keys.include?(k) }

        # key warnings
        override_keys = override_arguments.keys
        ignored_keys = arguments.keys & override_keys
        unless ignored_keys.empty?
          onoe "Some arguments to #{description} will be ignored -- :#{unknown_keys.inspect} (overridden)."
        end

        # extract executable
        executable = arguments.key?(:executable) ? arguments.delete(:executable) : nil

        arguments = default_arguments.merge arguments
        arguments.merge! override_arguments

        [executable, arguments]
      end

      sig { returns(Cask) }
      attr_reader :cask

      sig { params(cask: Cask, dsl_args: T.anything).void }
      def initialize(cask, *dsl_args)
        @cask = cask
        @dirmethod = T.let(nil, T.nilable(Symbol))
        @dsl_args = T.let(dsl_args.deep_dup, T::Array[T.anything])
        @dsl_key = T.let(nil, T.nilable(Symbol))
        @english_article = T.let(nil, T.nilable(String))
        @english_name = T.let(nil, T.nilable(String))
        @sort_order = T.let(nil, T.nilable(T::Hash[T.class_of(AbstractArtifact), Integer]))
      end

      sig { returns(Config) }
      def config
        cask.config
      end

      sig { returns(String) }
      def to_s
        "#{summarize} (#{self.class.english_name})"
      end

      sig { returns(T::Array[T.anything]) }
      def to_args
        @dsl_args.compact_blank
      end
    end
  end
end
