# typed: strict
# frozen_string_literal: true

require "development_tools"
require "cask/exceptions"
require "system_command"
require "utils/output"

module Cask
  # Helper module for quarantining files.
  module Quarantine
    extend SystemCommand::Mixin
    extend ::Utils::Output::Mixin

    class SigningIdentity < T::Struct
      const :requirement, String
    end

    QUARANTINE_ATTRIBUTE = "com.apple.quarantine"
    # https://github.com/apple-oss-distributions/WebKit/blob/WebKit-7618.2.12.11.6/Source/WebCore/PAL/pal/spi/mac/QuarantineSPI.h#L40-L45
    USER_APPROVED_FLAG = 0x0040

    sig { returns(T.nilable(Pathname)) }
    def self.xattr
      @xattr ||= T.let(DevelopmentTools.locate("xattr"), T.nilable(Pathname))
    end
    private_class_method :xattr

    sig { returns(T::Boolean) }
    def self.xattr_available?
      xattr = self.xattr
      return false if xattr.nil?

      system_command(xattr, args: ["-h"], print_stderr: false).success?
    end

    sig { returns([Symbol, T.nilable(String)]) }
    def self.check_quarantine_support
      [:quarantine_unavailable, nil]
    end

    sig { returns(T::Boolean) }
    def self.available?
      @quarantine_support ||= T.let(check_quarantine_support, T.nilable([Symbol, T.nilable(String)]))

      @quarantine_support[0] == :quarantine_available
    end

    sig { params(file: T.nilable(T.any(String, Pathname))).returns(T.nilable(T::Boolean)) }
    def self.detect(file)
      return if file.nil?

      odebug "Verifying Gatekeeper status of #{file}"

      quarantine_status = !status(file).empty?

      odebug "#{file} is #{quarantine_status ? "quarantined" : "not quarantined"}"

      quarantine_status
    end

    sig { params(file: T.any(String, Pathname)).returns(String) }
    def self.status(file)
      xattr = self.xattr
      raise "unexpected nil xattr" if xattr.nil?

      system_command(xattr,
                     args:         ["-p", QUARANTINE_ATTRIBUTE, file],
                     print_stderr: false).stdout.rstrip
    end

    sig { params(file: T.any(String, Pathname)).returns(T::Boolean) }
    def self.user_approved?(file)
      return false if xattr.nil?

      quarantine_status = status(file)
      return false if quarantine_status.empty?

      quarantine_status.split(";").fetch(0).to_i(16).anybits?(USER_APPROVED_FLAG)
    end

    sig { params(download_path: T.nilable(Pathname)).void }
    def self.inherit_user_approval!(download_path: nil)
      return if !download_path || !detect(download_path)

      # Preserve quarantine provenance so Gatekeeper still checks the upgraded app while carrying forward
      # the user's approval only after the upgrade path verifies that its signing identity is unchanged.
      # https://developer.apple.com/forums/thread/706442
      odebug "Inheriting user approval for #{download_path}"

      xattr = self.xattr
      raise "unexpected nil xattr" if xattr.nil?

      quarantiner = system_command(xattr,
                                   args:         [
                                     "-w",
                                     QUARANTINE_ATTRIBUTE,
                                     status(download_path).sub(/\A[0-9a-f]+/i) do |flags|
                                       (flags.to_i(16) | USER_APPROVED_FLAG).to_s(16).rjust(flags.length, "0")
                                     end,
                                     download_path,
                                   ],
                                   print_stderr: false)

      return if quarantiner.success?

      raise CaskQuarantineReleaseError.new(download_path, quarantiner.stderr)
    end

    sig { params(_file: T.any(String, Pathname)).returns(T.nilable(SigningIdentity)) }
    def self.signing_identity(_file); end

    sig {
      params(_file: T.any(String, Pathname), _identity: SigningIdentity)
        .returns(T.nilable(T::Boolean))
    }
    def self.signing_identity_match(_file, _identity); end

    sig { params(attribute: String).returns(String) }
    def self.toggle_no_translocation_bit(attribute)
      fields = attribute.split(";")

      # Fields: status, epoch, download agent, event ID
      # Let's toggle the app translocation bit, bit 8
      # http://www.openradar.me/radar?id=5022734169931776

      fields[0] = (fields.fetch(0).to_i(16) | 0x0100).to_s(16).rjust(4, "0")

      fields.join(";")
    end

    # Fully remove quarantine only when explicitly requested; upgrades preserve it and inherit approval above.
    sig { params(download_path: T.nilable(Pathname)).void }
    def self.release!(download_path: nil)
      return if !download_path || !detect(download_path)

      odebug "Releasing #{download_path} from quarantine"

      xattr = self.xattr
      raise "unexpected nil xattr" if xattr.nil?

      quarantiner = system_command(xattr,
                                   args:         [
                                     "-d",
                                     QUARANTINE_ATTRIBUTE,
                                     download_path,
                                   ],
                                   print_stderr: false)

      return if quarantiner.success?

      raise CaskQuarantineReleaseError.new(download_path, quarantiner.stderr)
    end

    sig { params(cask: T.nilable(Cask), download_path: T.nilable(Pathname), action: T::Boolean).void }
    def self.cask!(cask: nil, download_path: nil, action: true)
      raise NotImplementedError
    end

    sig { params(from: T.nilable(Pathname), to: T.nilable(Pathname)).void }
    def self.propagate(from: nil, to: nil)
      return if from.nil? || to.nil?

      raise CaskError, "#{from} was not quarantined properly." unless detect(from)

      odebug "Propagating quarantine from #{from} to #{to}"

      quarantine_status = toggle_no_translocation_bit(status(from))

      resolved_paths = Pathname.glob(to/"**/*", File::FNM_DOTMATCH).reject(&:symlink?)

      system_command!("/usr/bin/xargs",
                      args:  [
                        "-0",
                        "--",
                        "chmod",
                        "-h",
                        "u+w",
                      ],
                      input: resolved_paths.join("\0"))

      xattr = self.xattr
      raise "unexpected nil xattr" if xattr.nil?

      quarantiner = system_command("/usr/bin/xargs",
                                   args:         [
                                     "-0",
                                     "--",
                                     xattr,
                                     "-w",
                                     QUARANTINE_ATTRIBUTE,
                                     quarantine_status,
                                   ],
                                   input:        resolved_paths.join("\0"),
                                   print_stderr: false)

      return if quarantiner.success?

      raise CaskQuarantinePropagationError.new(to, quarantiner.stderr)
    end

    sig { params(from: Pathname, to: Pathname, command: T.class_of(SystemCommand)).void }
    def self.copy_xattrs(from, to, command:)
      raise NotImplementedError
    end

    # Ensures that Homebrew has permission to update apps on macOS Ventura.
    # This may be granted either through the App Management toggle or the Full Disk Access toggle.
    # The system will only show a prompt for App Management, so we ask the user to grant that.
    sig { params(app: Pathname, command: T.class_of(SystemCommand)).returns(T::Boolean) }
    def self.app_management_permissions_granted?(app:, command:)
      return true unless app.directory?

      # To get macOS to prompt the user for permissions, we need to actually attempt to
      # modify a file in the app.
      test_file = app/".homebrew-write-test"

      # We can't use app.writable? here because that conflates several access checks,
      # including both file ownership and whether system permissions are granted.
      # Here we just want to check whether sudo would be needed.
      looks_writable_without_sudo = if app.owned?
        app.lstat.mode.anybits?(0200)
      elsif app.grpowned?
        app.lstat.mode.anybits?(0020)
      else
        app.lstat.mode.anybits?(0002)
      end

      if looks_writable_without_sudo
        begin
          File.write(test_file, "")
          test_file.delete
          return true
        rescue Errno::EACCES, Errno::EPERM
          # Using error handler below
        end
      else
        begin
          command.run!(
            "touch",
            args:         [
              test_file,
            ],
            print_stderr: false,
            sudo:         true,
          )
          command.run!(
            "rm",
            args:         [
              test_file,
            ],
            print_stderr: false,
            sudo:         true,
          )
          return true
        rescue ErrorDuringExecution => e
          # We only want to handle "touch" errors here; propagate "sudo" errors up
          raise e unless e.stderr.include?("touch: #{test_file}: Operation not permitted")
        end
      end

      # Allow undocumented way to skip the prompt.
      if ENV["HOMEBREW_NO_APP_MANAGEMENT_PERMISSIONS_PROMPT"]
        opoo <<~EOF
          Your terminal does not have App Management permissions, so Homebrew will delete and reinstall the app.
          This may result in some configurations (like notification settings or location in the Dock/Launchpad) being lost.
          To fix this, go to System Settings → Privacy & Security → App Management and add or enable your terminal.
        EOF
      end

      false
    end
  end
end

require "extend/os/cask/quarantine"
