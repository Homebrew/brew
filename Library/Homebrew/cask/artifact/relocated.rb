# typed: true
# frozen_string_literal: true

require "cask/artifact/abstract_artifact"

module Cask
  module Artifact
    # Superclass for all artifacts which have a source and a target location.
    #
    # @api private
    class Relocated < AbstractArtifact
      def self.from_args(cask, *args)
        source_string, target_hash = args

        if target_hash
          raise CaskInvalidError, cask unless target_hash.respond_to?(:keys)

          target_hash.assert_valid_keys(:target)
        end

        target_hash ||= {}

        new(cask, source_string, **target_hash)
      end

      def resolve_target(target, base_dir: config.public_send(self.class.dirmethod))
        target = Pathname(target)

        if target.relative?
          return target.expand_path if target.descend.first.to_s == "~"
          return base_dir/target if base_dir
        end

        target
      end

      sig {
        params(cask: Cask, source: T.nilable(T.any(String, Pathname)), target_hash: T.any(String, Pathname))
          .void
      }
      def initialize(cask, source, **target_hash)
        super(cask, source, **target_hash)

        target = target_hash[:target]
        @source_string = source.to_s
        @target_string = target.to_s
      end

      def source
        @source ||= begin
          base_path = cask.staged_path
          base_path = base_path.join(cask.url.only_path) if cask.url&.only_path.present?
          base_path.join(@source_string)
        end
      end

      def target
        @target ||= resolve_target(@target_string.presence || source.basename)
      end

      def to_a
        [@source_string].tap do |ary|
          ary << { target: @target_string } unless @target_string.empty?
        end
      end

      sig { override.returns(String) }
      def summarize
        target_string = @target_string.empty? ? "" : " -> #{@target_string}"
        "#{@source_string}#{target_string}"
      end

      private

      ALT_NAME_ATTRIBUTE = "com.apple.metadata:kMDItemAlternateNames"

      # Try to make the asset searchable under the target name. Spotlight
      # respects this attribute for many filetypes, but ignores it for App
      # bundles. Alfred 2.2 respects it even for App bundles.
      def add_altname_metadata(file, altname, command: nil)
        return if altname.to_s.casecmp(file.basename.to_s).zero?

        odebug "Adding #{ALT_NAME_ATTRIBUTE} metadata"
        altnames = command.run("/usr/bin/xattr",
                               args:         ["-p", ALT_NAME_ATTRIBUTE, file],
                               print_stderr: false).stdout.sub(/\A\((.*)\)\Z/, '\1')
        odebug "Existing metadata is: #{altnames}"
        altnames.concat(", ") unless altnames.empty?
        altnames.concat(%Q("#{altname}"))
        altnames = "(#{altnames})"

        # Some packages are shipped as u=rx (e.g. Bitcoin Core)
        command.run!("/bin/chmod", args: ["--", "u+rw", file, file.realpath])

        command.run!("/usr/bin/xattr",
                     args:         ["-w", ALT_NAME_ATTRIBUTE, altnames, file],
                     print_stderr: false)
      end

      def printable_target
        target.to_s.sub(/^#{Dir.home}(#{File::SEPARATOR}|$)/, "~/")
      end
    end
  end
end
