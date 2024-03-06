# typed: true
# frozen_string_literal: true

require "attrable"
require "extend/object/deep_dup"

module Cask
  module Artifact
    # Abstract superclass for all artifacts.
    class AbstractArtifact
      extend T::Helpers
      abstract!

      include Comparable
      extend Attrable

      def self.english_name
        @english_name ||= T.must(name).sub(/^.*:/, "").gsub(/(.)([A-Z])/, '\1 \2')
      end

      def self.english_article
        @english_article ||= /^[aeiou]/i.match?(english_name) ? "an" : "a"
      end

      def self.dsl_key
        @dsl_key ||= T.must(name).sub(/^.*:/, "").gsub(/(.)([A-Z])/, '\1_\2').downcase.to_sym
      end

      def self.dirmethod
        @dirmethod ||= :"#{dsl_key}dir"
      end

      sig { abstract.returns(String) }
      def summarize; end

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

      def <=>(other)
        return unless other.class < AbstractArtifact
        return 0 if instance_of?(other.class)

        @@sort_order ||= [ # rubocop:disable Style/ClassVars
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
        ].each_with_index.flat_map { |classes, i| Array(classes).map { |c| [c, i] } }.to_h

        (@@sort_order[self.class] <=> @@sort_order[other.class]).to_i
      end

      # TODO: this sort of logic would make more sense in dsl.rb, or a
      #       constructor called from dsl.rb, so long as that isn't slow.
      def self.read_script_arguments(arguments, stanza, default_arguments = {}, override_arguments = {}, key = nil)
        # TODO: when stanza names are harmonized with class names,
        #       stanza may not be needed as an explicit argument
        description = key ? "#{stanza} #{key.inspect}" : stanza.to_s

        # backward-compatible string value
        arguments = if arguments.is_a?(String)
          { executable: arguments }
        else
          # Avoid mutating the original argument
          arguments.dup
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

      attr_reader :cask

      def initialize(cask, *dsl_args)
        @cask = cask
        @dsl_args = dsl_args.deep_dup
      end

      def config
        cask.config
      end

      sig { returns(String) }
      def to_s
        "#{summarize} (#{self.class.english_name})"
      end

      def to_args
        @dsl_args.compact_blank
      end
    end
  end
end
