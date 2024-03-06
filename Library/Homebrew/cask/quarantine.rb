# typed: true
# frozen_string_literal: true

require "development_tools"
require "cask/exceptions"
require "system_command"

module Cask
  # Helper module for quarantining files.
  module Quarantine
    extend SystemCommand::Mixin

    QUARANTINE_ATTRIBUTE = "com.apple.quarantine"

    QUARANTINE_SCRIPT = (HOMEBREW_LIBRARY_PATH/"cask/utils/quarantine.swift").freeze
    COPY_XATTRS_SCRIPT = (HOMEBREW_LIBRARY_PATH/"cask/utils/copy-xattrs.swift").freeze

    def self.swift
      @swift ||= begin
        # /usr/bin/swift (which runs via xcrun) adds `/usr/local/include` to the top of the include path,
        # which allows really broken local setups to break our Swift usage here. Using the underlying
        # Swift executable directly however (returned by `xcrun -find`) avoids this CPATH mess.
        xcrun_swift = ::Utils.popen_read("/usr/bin/xcrun", "-find", "swift", err: :close).chomp
        if $CHILD_STATUS.success? && File.executable?(xcrun_swift)
          xcrun_swift
        else
          DevelopmentTools.locate("swift")
        end
      end
    end
    private_class_method :swift

    def self.xattr
      @xattr ||= DevelopmentTools.locate("xattr")
    end
    private_class_method :xattr

    def self.swift_target_args
      ["-target", "#{Hardware::CPU.arch}-apple-macosx#{MacOS.version}"]
    end
    private_class_method :swift_target_args

    sig { returns(Symbol) }
    def self.check_quarantine_support
      odebug "Checking quarantine support"

      if xattr.nil? || !system_command(xattr, args: ["-h"], print_stderr: false).success?
        odebug "There's no working version of `xattr` on this system."
        :xattr_broken
      elsif swift.nil?
        odebug "Swift is not available on this system."
        :no_swift
      else
        api_check = system_command(swift,
                                   args:         [*swift_target_args, QUARANTINE_SCRIPT],
                                   print_stderr: false)

        case api_check.exit_status
        when 2
          odebug "Quarantine is available."
          :quarantine_available
        else
          odebug "Unknown support status"
          :unknown
        end
      end
    end

    def self.available?
      @status ||= check_quarantine_support

      @status == :quarantine_available
    end

    def self.detect(file)
      return if file.nil?

      odebug "Verifying Gatekeeper status of #{file}"

      quarantine_status = !status(file).empty?

      odebug "#{file} is #{quarantine_status ? "quarantined" : "not quarantined"}"

      quarantine_status
    end

    def self.status(file)
      system_command(xattr,
                     args:         ["-p", QUARANTINE_ATTRIBUTE, file],
                     print_stderr: false).stdout.rstrip
    end

    def self.toggle_no_translocation_bit(attribute)
      fields = attribute.split(";")

      # Fields: status, epoch, download agent, event ID
      # Let's toggle the app translocation bit, bit 8
      # http://www.openradar.me/radar?id=5022734169931776

      fields[0] = (fields[0].to_i(16) | 0x0100).to_s(16).rjust(4, "0")

      fields.join(";")
    end

    def self.release!(download_path: nil)
      return unless detect(download_path)

      odebug "Releasing #{download_path} from quarantine"

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

    def self.cask!(cask: nil, download_path: nil, action: true)
      return if cask.nil? || download_path.nil?

      return if detect(download_path)

      odebug "Quarantining #{download_path}"

      quarantiner = system_command(swift,
                                   args:         [
                                     *swift_target_args,
                                     QUARANTINE_SCRIPT,
                                     download_path,
                                     cask.url.to_s,
                                     cask.homepage.to_s,
                                   ],
                                   print_stderr: false)

      return if quarantiner.success?

      case quarantiner.exit_status
      when 2
        raise CaskQuarantineError.new(download_path, "Insufficient parameters")
      else
        raise CaskQuarantineError.new(download_path, quarantiner.stderr)
      end
    end

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
                        "/bin/chmod",
                        "-h",
                        "u+w",
                      ],
                      input: resolved_paths.join("\0"))

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
      odebug "Copying xattrs from #{from} to #{to}"

      command.run!(
        swift,
        args: [
          *swift_target_args,
          COPY_XATTRS_SCRIPT,
          from,
          to,
        ],
        sudo: !to.writable?,
      )
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
        (app.lstat.mode & 0200) != 0
      elsif app.grpowned?
        (app.lstat.mode & 0020) != 0
      else
        (app.lstat.mode & 0002) != 0
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

      opoo <<~EOF
        Your terminal does not have App Management permissions, so Homebrew will delete and reinstall the app.
        This may result in some configurations (like notification settings or location in the Dock/Launchpad) being lost.
        To fix this, go to System Settings > Privacy & Security > App Management and add or enable your terminal.
      EOF

      false
    end
  end
end
