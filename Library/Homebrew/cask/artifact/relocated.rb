# typed: strict
# frozen_string_literal: true

require "cask/artifact/abstract_artifact"
require "extend/hash/keys"

module Cask
  module Artifact
    # Superclass for all artifacts which have a source and a target location.
    class Relocated < AbstractArtifact
      sig {
        params(cask: Cask, source_string: T.nilable(String), target_hash: DirectivesType).returns(Relocated)
      }
      def self.from_args(cask, source_string = nil, **target_hash)
        target_hash.assert_valid_keys(:target)

        new(cask, source_string, **target_hash)
      end

      sig { overridable.params(target: T.any(String, Pathname), base_dir: T.nilable(Pathname)).returns(Pathname) }
      def resolve_target(target, base_dir: config.public_send(self.class.dirmethod))
        target = Pathname(target)

        if target.relative?
          return target.expand_path if target.descend.first.to_s == "~"
          return base_dir/target if base_dir
        end

        target
      end

      sig { params(cask: Cask, source: T.nilable(T.any(String, Pathname)), target_hash: DirectivesType).void }
      def initialize(cask, source, **target_hash)
        super

        target = target_hash[:target]
        @source = T.let(nil, T.nilable(Pathname))
        @source_string = T.let(source.to_s, String)
        @target = T.let(nil, T.nilable(Pathname))
        @target_string = T.let(target.to_s, String)
      end

      sig { returns(Pathname) }
      def source
        @source ||= begin
          base_path = cask.staged_path
          base_path = base_path.join(T.must(cask.url).only_path) if cask.url&.only_path.present?
          base_path.join(@source_string)
        end
      end

      sig { returns(Pathname) }
      def target
        @target ||= resolve_target(@target_string.presence || source.basename)
      end

      sig { returns(T::Array[T.anything]) }
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
      private_constant :ALT_NAME_ATTRIBUTE

      # Try to make the asset searchable under the target name. Spotlight
      # respects this attribute for many filetypes, but ignores it for App
      # bundles. Alfred 2.2 respects it even for App bundles.
      sig { params(file: Pathname, altname: Pathname, command: T.class_of(SystemCommand)).returns(T.nilable(SystemCommand::Result)) }
      def add_altname_metadata(file, altname, command:)
        return if altname.to_s.casecmp(file.basename.to_s)&.zero?

        odebug "Adding #{ALT_NAME_ATTRIBUTE} metadata"
        altnames = command.run("/usr/bin/xattr",
                               args:         ["-p", ALT_NAME_ATTRIBUTE, file],
                               print_stderr: false).stdout.sub(/\A\((.*)\)\Z/, '\1')
        odebug "Existing metadata is: #{altnames}"
        altnames.concat(", ") unless altnames.empty?
        altnames.concat(%Q("#{altname}"))
        altnames = "(#{altnames})"

        # Some packages are shipped as u=rx (e.g. Bitcoin Core)
        command.run!("chmod",
                     args: ["--", "u+rw", file, file.realpath],
                     sudo: !file.writable? || !file.realpath.writable?)

        command.run!("/usr/bin/xattr",
                     args:         ["-w", ALT_NAME_ATTRIBUTE, altnames, file],
                     print_stderr: false,
                     sudo:         !file.writable?)
      end

      sig { returns(String) }
      def printable_target
        target.to_s.sub(/^#{Dir.home}(#{File::SEPARATOR}|$)/, "~/")
      end
    end
  end
end

require "extend/os/cask/artifact/relocated"
