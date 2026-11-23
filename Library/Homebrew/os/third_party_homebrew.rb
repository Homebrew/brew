# typed: strict
# frozen_string_literal: true

module OS
  # Local evidence of a third-party Homebrew configuration and its support policy.
  class ThirdPartyHomebrew < T::Struct
    const :tier, T.any(Integer, Symbol), default: 3
    const :diagnostic, String, default: "Found a third-party Homebrew wrapper on this machine."
    const :issues_url, T.nilable(String)
    const :files, T::Hash[Symbol, String], default: {}
    const :presence_file, T.nilable(String)
    const :repository_owner, T.nilable(String)
    const :prefixes, T::Hash[Symbol, String], default: {}
    const :command, T.nilable(Regexp)
    const :api_delay_hours, T.nilable(Integer)
    const :check, T.nilable(Method)

    sig { returns(T::Boolean) }
    def owns_repository?
      return false unless repository_owner

      require "etc"
      Etc.getpwuid(HOMEBREW_REPOSITORY.stat.uid)&.name == repository_owner
    rescue ArgumentError, SystemCallError
      false
    end

    sig { returns(T::Boolean) }
    private_class_method def self.nix_homebrew?
      HOMEBREW_REPOSITORY.basename.to_s == ".homebrew-is-managed-by-nix" ||
        (HOMEBREW_PREFIX/".managed_by_nix_darwin").exist? ||
        (ENV["HOMEBREW_UPDATE_BEFORE"] == "nix" && ENV["HOMEBREW_UPDATE_AFTER"] == "nix")
    end

    sig { returns(T::Boolean) }
    private_class_method def self.nix_darwin?
      ENV.fetch("HOMEBREW_BUNDLE_FILE", "").start_with?("/nix/store/") ||
        ARGV.each_cons(2).any? { |arg, value| arg == "--file" && value.start_with?("/nix/store/") } ||
        ARGV.any? { |arg| arg.start_with?("--file=/nix/store/") }
    end

    sig { returns(T::Boolean) }
    private_class_method def self.wrapper?
      !ENV.fetch("HOMEBREW_BREW_WRAPPER", "").empty?
    end

    certificate = "run/endpoint-protection-proxy-ca-crt.pem"
    managed = "A third-party tool manages this Homebrew installation or its package list."
    provisioned = "A third-party provisioning tool invoked Homebrew."

    # Check unsupported configurations first. Files can outlast the software that installed them.
    configurations = {
      # https://help.aikido.dev/aikido-device-protection/miscellaneous-aikido-endpoint/ssl-certificate-errors
      # https://github.com/Homebrew/brew/issues/24665#issuecomment-7003869805
      aikido:       new(
        tier:            :unsupported,
        api_delay_hours: 48,
        diagnostic:      "Found a certificate for third-party software that can intercept Homebrew downloads.",
        files:           {
          macos: "/Library/Application Support/AikidoSecurity/EndpointProtection/#{certificate}",
          linux: "/var/lib/aikidosecurity/endpoint-protection/#{certificate}",
        },
      ),
      # https://workbrew.com/docs/homebrew-management
      workbrew:     new(
        repository_owner: "workbrew",
        presence_file:    "/opt/workbrew/bin/brew",
        diagnostic:       "A third-party management tool's service account owns this Homebrew repository.",
        issues_url:       "https://console.workbrew.com/contact",
      ),
      # https://github.com/macadmins/carafe#minimum-version-enforcement
      carafe:       new(
        files:      { macos: "/opt/macadmins/bin/carafe" },
        issues_url: "https://github.com/macadmins/carafe/issues",
      ),
      # https://github.com/zhaofengli/nix-homebrew/blob/aeb2069920742d0d6570089e8b3b8620050bacf2/modules/default.nix#L115-L125
      nix_homebrew: new(
        check:      method(:nix_homebrew?),
        diagnostic: managed,
        issues_url: "https://github.com/zhaofengli/nix-homebrew/issues",
      ),
      # https://github.com/nix-darwin/nix-darwin/blob/8c62fba0854ba15c8917aed18894dbccb48a3777/modules/homebrew.nix#L182
      nix_darwin:   new(
        check:      method(:nix_darwin?),
        diagnostic: managed,
        issues_url: "https://github.com/nix-darwin/nix-darwin/issues",
      ),
      # https://github.com/boxen/puppet-homebrew/blob/master/lib/facter/homebrew_root.rb
      boxen:        new(prefixes:   { macos: File.join(ENV.fetch("BOXEN_HOME", "/opt/boxen"), "homebrew") },
                        diagnostic: managed),
      # https://github.com/ansible-collections/community.general/blob/main/plugins/modules/homebrew.py
      ansible:      new(command: /\A(?:ansible(?:-playbook|-pull)?|AnsiballZ_\w+\.py)\z/, diagnostic: provisioned,
                        issues_url: "https://github.com/ansible-collections/community.general/issues"),
      # https://github.com/puppetjoy/puppet-homebrew/blob/main/lib/puppet/provider/package/homebrew.rb
      puppet:       new(command: /\Apuppet\z/, diagnostic: provisioned,
                        issues_url: "https://github.com/puppetjoy/puppet-homebrew/issues"),
      # https://github.com/franckverrot/terraform-provider-homebrew
      terraform:    new(command: /\Aterraform(?:-provider-homebrew(?:_v[\w.+-]+)?)?\z/, diagnostic: provisioned,
                        issues_url: "https://github.com/franckverrot/terraform-provider-homebrew/issues"),
      # https://github.com/chef/chef/blob/main/lib/chef/provider/package/homebrew.rb
      chef:         new(command: /\Achef-(?:client|solo|apply)\z/, diagnostic: provisioned,
                        issues_url: "https://github.com/chef/chef/issues"),
      wrapper:      new(check: method(:wrapper?), diagnostic: "A third-party wrapper invoked Homebrew."),
    }
    CONFIGURATIONS = T.let(configurations.freeze, T::Hash[Symbol, ThirdPartyHomebrew])

    # Only the script operand identifies a provisioner. Stop at unknown options and inline code.
    sig { params(executable: String, arguments: T.nilable(String)).returns(T.nilable(String)) }
    def self.command_name(executable, arguments)
      command = File.basename(executable)
      case command
      when /\Apython[\d.]*\z/i
        flags = /\A-[bBdEiIOPqRsSuvx]+\z/
        option_with_value = /\A(?:-[bBdEiIOPqRsSuvx]*[WX]|--check-hash-based-pycs\z)/
      when /\Aruby[\d.]*\z/i
        flags = /\A(?:-[adlnpsSvwy]+|-W[012]?|--debug|--verbose|--disable-gems)\z/
        option_with_value = /\A-[adlnpsSvwy]*[CEFIr]/
      else
        return command
      end

      args = arguments.to_s.split
      while (option = args.first)&.start_with?("-")
        args.shift
        break if option == "--"
        next if flags.match?(option)

        name = option[option_with_value]
        return unless name

        args.shift if option == name
      end
      script = args.first
      File.basename(script) if script
    end

    sig { params(macos: T::Boolean).returns(T.nilable(ThirdPartyHomebrew)) }
    def self.detect(macos:)
      platform = macos ? :macos : :linux
      CONFIGURATIONS.each_value do |configuration|
        return configuration if configuration.prefixes[platform] == HOMEBREW_PREFIX.to_s
        return configuration if configuration.owns_repository?

        file = configuration.files[platform] || configuration.files[:all]
        return configuration if (file && File.file?(file)) || configuration.check&.call
      end

      require "utils/popen"
      pid = Process.ppid
      seen = Set.new
      while pid > 1 && seen.add?(pid)
        row = ::Utils.popen_read_text("/bin/ps", "-ww", "-p", pid.to_s, "-o", "ppid=,args=", err: :close)
        parent, executable, arguments = row.b.split(" ", 3)
        break if parent.nil? || executable.nil?

        command = command_name(executable, arguments)
        provider = CONFIGURATIONS.each_value.find { |configuration| configuration.command&.match?(command) }
        return provider if provider

        pid = parent.to_i
      end
      nil
    end
  end
end
