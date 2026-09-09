# typed: strict
# frozen_string_literal: true

require "cask/artifact/abstract_artifact"

module Cask
  module Artifact
    class Deb < AbstractArtifact
      sig { returns(String) }
      attr_reader :path

      sig { params(cask: Cask, path: T.any(String, Pathname)).returns(T.attached_class) }
      def self.from_args(cask, path)
        new(cask, path)
      end

      sig { params(cask: Cask, path: T.any(String, Pathname)).void }
      def initialize(cask, path)
        super
        @path = T.let(path.to_s, String)
      end

      sig { override.returns(String) }
      def summarize
        path
      end

      sig {
        params(
          command:  T.class_of(SystemCommand),
          verbose:  T::Boolean,
          _options: T.anything,
        ).void
      }
      def install_phase(command: SystemCommand, verbose: false, **_options)
        ohai "Installing #{format_label} package #{Formatter.identifier(path)} with `sudo` (which may request your password)..."
        command.run!(
          "sudo",
          args:         install_args,
          print_stdout: true,
        )
      end

      sig {
        params(
          command:  T.class_of(SystemCommand),
          verbose:  T::Boolean,
          _options: T.anything,
        ).void
      }
      def uninstall_phase(command: SystemCommand, verbose: false, **_options)
        ohai "Uninstalling #{format_label} package #{Formatter.identifier(path)}..."
        command.run!(
          "sudo",
          args:         uninstall_args(command:),
          print_stdout: true,
        )
      end

      private

      sig { returns(String) }
      def format_label
        case File.extname(path)
        when ".deb"  then "DEB"
        when ".rpm"  then "RPM"
        when ".apk"  then "APK"
        when ".pkg"  then "PACMAN"
        else "native"
        end
      end

      sig { returns(T::Array[String]) }
      def install_args
        case File.extname(path)
        when ".deb"
          ["dpkg", "-i", cask.staged_path.join(path)]
        when ".rpm"
          ["rpm", "-ivh", cask.staged_path.join(path)]
        when ".apk"
          ["apk", "add", "--allow-untrusted", cask.staged_path.join(path)]
        when ".pkg"
          ["pacman", "--noconfirm", "-U", cask.staged_path.join(path)]
        else
          raise CaskError, "Unsupported package format: #{File.extname(path)}"
        end
      end

      sig { params(command: T.class_of(SystemCommand)).returns(T::Array[String]) }
      def uninstall_args(command:)
        name = package_name(command:)
        case File.extname(path)
        when ".deb"
          ["dpkg", "--purge", "--force-depends", name]
        when ".rpm"
          ["rpm", "-e", "--nodeps", name]
        when ".apk"
          ["apk", "del", name]
        when ".pkg"
          ["pacman", "--noconfirm", "-R", name]
        else
          raise CaskError, "Unsupported package format: #{File.extname(path)}"
        end
      end

      sig { params(command: T.class_of(SystemCommand)).returns(String) }
      def package_name(command:)
        result = case File.extname(path)
        when ".deb"
          command.run(
            "dpkg-deb",
            args:         ["--showformat", "${Package}", "-W", cask.staged_path.join(path)],
            print_stderr: false,
          )
        when ".rpm"
          command.run(
            "rpm",
            args:         ["-qp", "--queryformat", "%{NAME}", cask.staged_path.join(path)],
            print_stderr: false,
          )
        when ".apk"
          basename = File.basename(path, ".apk")
          return basename.rpartition("-").first
        when ".pkg"
          basename = File.basename(path)
          basename = basename.sub(/\.pkg\.tar\.\w+$/, "")
          return basename.rpartition("-").first
        else
          raise CaskError, "Unsupported package format: #{File.extname(path)}"
        end

        name = result.stdout.strip
        raise CaskError, "Could not determine package name from: #{path}" if name.empty?

        name
      end
    end
  end
end
