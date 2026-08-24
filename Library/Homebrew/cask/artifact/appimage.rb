# typed: strict
# frozen_string_literal: true

require "digest"
require "cask/artifact/binary"
require "cask/artifact/symlinked"
require "utils/path"

module Cask
  module Artifact
    # Artifact corresponding to the `app_image` stanza.
    class AppImage < Symlinked
      sig {
        override.params(
          cask:          Cask,
          source_string: T.any(String, Pathname),
          target_hash:   T.untyped,
        ).returns(T.attached_class)
      }
      def self.from_args(cask, source_string, target_hash = nil)
        if target_hash
          raise CaskInvalidError, cask unless target_hash.respond_to?(:keys)

          target_hash.assert_valid_keys(:target, :binary)
        end

        new(cask, source_string, **(target_hash || {}))
      end

      sig {
        params(
          cask:   Cask,
          source: T.any(String, Pathname),
          binary: T.nilable(T.any(String, Pathname)),
          target: T.nilable(T.any(String, Pathname)),
        ).void
      }
      def initialize(cask, source, binary: nil, target: nil)
        target ? super(cask, source, target:) : super(cask, source)
        @binary_target = T.let(binary&.to_s, T.nilable(String))
        @binary = T.let(binary ? Binary.new(cask, source, target: binary) : nil, T.nilable(Binary))
      end

      sig { override.params(target: T.any(String, Pathname), base_dir: T.nilable(Pathname)).returns(Pathname) }
      def resolve_target(target, base_dir: nil)
        Pathname.new("#{config.appimagedir}/#{target}")
      end

      sig {
        override.params(
          force:    T::Boolean,
          adopt:    T::Boolean,
          command:  T.class_of(SystemCommand),
          binaries: T::Boolean,
          _options: T.anything,
        ).void
      }
      def link(force: false, adopt: false, command: SystemCommand, binaries: true, **_options)
        super
        if !source.executable? && source.writable?
          FileUtils.chmod "+x", source
        elsif !source.executable?
          command.run!("chmod", args: ["+x", source], sudo: true)
        end

        @binary&.install_phase(force:, adopt:, command:) if binaries
        install_desktop_file(command)
      end

      sig { params(command: T.class_of(SystemCommand), _options: T.anything).void }
      def uninstall_phase(command: SystemCommand, **_options)
        Utils.gain_permissions_remove(desktop_file_path, command:) if desktop_file_owned_by_this_install?
        @binary&.uninstall_phase(command:)
        super
      end

      sig { override.returns(T::Array[T.anything]) }
      def to_args
        [@source_string].tap do |args|
          options = {}
          options[:target] = @target_string unless @target_string.empty?
          options[:binary] = @binary_target if @binary_target
          args << options unless options.empty?
        end
      end

      private

      sig { params(command: T.class_of(SystemCommand)).void }
      def install_desktop_file(command)
        Dir.mktmpdir("homebrew-appimage", HOMEBREW_TEMP) do |tmpdir|
          extraction_dir = Pathname(tmpdir)
          result = command.run(source, args: ["--appimage-extract"], chdir: extraction_dir, print_stderr: false)
          next unless result.success?

          appimage_root = extraction_dir/"squashfs-root"
          bundled_desktop_file = appimage_root.glob("*.desktop").first
          next unless bundled_desktop_file

          contents = bundled_desktop_file.read
          executable_pattern = /^Exec=(?:"(?:\\.|[^"])*"|\S+)(.*)$/
          next unless contents.match?(executable_pattern)

          contents.sub!(executable_pattern) do
            "Exec=#{desktop_exec_path}#{Regexp.last_match(1)}"
          end
          contents.gsub!(/^TryExec=.*$/, "TryExec=#{desktop_exec_path}")

          integration_dir.mkpath
          if (icon = bundled_icon(appimage_root))
            installed_icon = integration_dir/"icon#{icon.extname}"
            FileUtils.cp icon, installed_icon
            contents.gsub!(/^Icon=.*$/, "Icon=#{installed_icon}")
          end
          installed_desktop_file.write(contents)

          Utils.gain_permissions_remove(desktop_file_path, command:) if desktop_file_takeover_allowed?
          if !desktop_file_path.exist? && !desktop_file_path.symlink?
            desktop_file_path.dirname.mkpath
            desktop_file_path.make_symlink(installed_desktop_file)
          end
        end
      end

      sig { returns(T::Boolean) }
      def desktop_file_owned_by_this_install?
        return false unless desktop_file_path.symlink?

        desktop_file_path.readlink.cleanpath == installed_desktop_file.cleanpath
      end

      sig { returns(T::Boolean) }
      def desktop_file_takeover_allowed?
        return false unless desktop_file_path.symlink?

        destination = desktop_file_path.readlink
        return false unless destination.absolute?

        destination = destination.cleanpath
        caskroom_path = cask.caskroom_path.expand_path
        return false unless ::Utils::Path.child_of?(caskroom_path, destination)

        components = destination.relative_path_from(caskroom_path).each_filename.to_a
        components.length == 4 &&
          components[1] == ".homebrew-appimage" &&
          components[2] == artifact_id &&
          components[3] == desktop_file_path.basename.to_s
      rescue ArgumentError
        false
      end

      sig { returns(Pathname) }
      def desktop_file_path
        xdg_data_home = ENV.fetch("HOMEBREW_XDG_DATA_HOME", "#{Dir.home}/.local/share")
        Pathname(xdg_data_home)/"applications/homebrew-#{cask.token}-appimage-#{artifact_id}.desktop"
      end

      sig { returns(Pathname) }
      def integration_dir
        cask.staged_path/".homebrew-appimage/#{artifact_id}"
      end

      sig { returns(Pathname) }
      def installed_desktop_file
        integration_dir/desktop_file_path.basename
      end

      sig { returns(String) }
      def artifact_id
        logical_target = target.relative_path_from(Pathname(config.appimagedir)).cleanpath
        Digest::SHA256.hexdigest(logical_target.to_s)
      end

      sig { params(appimage_root: Pathname).returns(T.nilable(Pathname)) }
      def bundled_icon(appimage_root)
        icon = appimage_root/".DirIcon"
        return unless icon.exist?

        icon = icon.realpath
        return unless ::Utils::Path.child_of?(appimage_root.realpath, icon)

        icon if icon.file?
      rescue Errno::ENOENT
        nil
      end

      sig { returns(String) }
      def desktop_exec_path
        path = target.to_s.gsub("%", "%%").gsub(/["`$\\]/) { |character| "\\#{character}" }
        path.match?(/\s/) ? %Q("#{path}") : path
      end
    end
  end
end
