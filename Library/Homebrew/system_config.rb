# typed: strict
# frozen_string_literal: true

require "hardware"
require "tap"
require "development_tools"
require "extend/ENV"
require "system_command"
require "git_repository"
require "utils/popen"

# Helper module for querying information about the system configuration.
module SystemConfig
  class << self
    include SystemCommand::Mixin

    sig { void }
    def initialize
      @clang = T.let(nil, T.nilable(Version))
      @clang_build = T.let(nil, T.nilable(Version))
    end

    sig { returns(Version) }
    def clang
      @clang ||= if DevelopmentTools.installed?
        DevelopmentTools.clang_version
      else
        Version::NULL
      end
    end

    sig { returns(Version) }
    def clang_build
      @clang_build ||= if DevelopmentTools.installed?
        DevelopmentTools.clang_build_version
      else
        Version::NULL
      end
    end

    sig { returns(GitRepository) }
    def homebrew_repo
      GitRepository.new(HOMEBREW_REPOSITORY)
    end

    sig { returns([T.nilable(String), T.nilable(String), T.nilable(String)]) }
    def homebrew_head_info
      @homebrew_head_info ||= T.let(
        homebrew_repo.head_info,
        T.nilable([T.nilable(String), T.nilable(String), T.nilable(String)]),
      )
    end

    sig { returns(String) }
    def branch
      homebrew_head_info[2] || "(none)"
    end

    sig { returns(String) }
    def head
      homebrew_head_info[0] || "(none)"
    end

    sig { returns(String) }
    def last_commit
      homebrew_head_info[1] || "never"
    end

    sig { returns(String) }
    def origin
      homebrew_repo.origin_url || "(none)"
    end

    sig { returns(String) }
    def describe_clang
      return "N/A" if clang.null?

      if clang_build.null?
        clang.to_s
      else
        "#{clang} build #{clang_build}"
      end
    end

    sig { returns(String) }
    def describe_homebrew_ruby
      "#{RUBY_VERSION} => #{RUBY_PATH}"
    end

    sig { returns(T.nilable(String)) }
    def hardware
      return if Hardware::CPU.type == :dunno

      "CPU: #{Hardware.cores_as_words}-core #{Hardware::CPU.bits}-bit #{Hardware::CPU.family}"
    end

    sig { returns(String) }
    def kernel
      Utils.popen_read_text("uname", "-m", err: :err).chomp
    end

    sig { returns(T.nilable(String)) }
    def windows_version; end

    sig { returns(String) }
    def describe_git
      return "N/A" unless Utils::Git.available?

      "#{Utils::Git.version} => #{Utils::Git.path}"
    end

    sig { returns(String) }
    def describe_curl
      out = system_command(Utils::Curl.curl_executable, args: ["--version"], verbose: false).stdout

      match_data = /^curl (?<curl_version>[\d.]+)/.match(out)
      if match_data
        "#{match_data[:curl_version]} => #{Utils::Curl.curl_path}"
      else
        "N/A"
      end
    end

    sig { params(tap: Tap, out: T.any(File, StringIO, IO)).void }
    def dump_tap_config(tap, out = $stdout)
      tap_name = case tap
      when CoreTap
        "Core tap"
      when CoreCaskTap
        "Core cask tap"
      else
        raise ArgumentError, "Unknown tap: #{tap}"
      end

      if tap.installed?
        out.puts "#{tap_name} origin: #{tap.remote}" if tap.remote != tap.default_remote
        head, last_commit, branch = tap.git_repository.head_info
        display_head = head || "(none)"
        out.puts "#{tap_name} HEAD: #{display_head}"
        display_commit = last_commit || "never"
        out.puts "#{tap_name} last commit: #{display_commit}"
        default_branches = %w[main master].freeze
        if default_branches.exclude?(branch)
          display_branch = branch || "(none)"
          out.puts "#{tap_name} branch: #{display_branch}"
        end
      end

      json_file = Homebrew::API::Internal.cached_packages_json_file_path
      if json_file.exist?
        modified_at = json_file.mtime.utc.strftime("%d %b %H:%M UTC")
        out.puts "#{tap_name} JSON: #{modified_at}"
      elsif !tap.installed?
        out.puts "#{tap_name}: N/A"
      end
    end

    sig { params(out: T.any(File, StringIO, IO)).void }
    def core_tap_config(out = $stdout)
      dump_tap_config(CoreTap.instance, out)
      dump_tap_config(CoreCaskTap.instance, out)
      return if Homebrew::EnvConfig.no_install_from_api?

      threshold = OS.third_party_homebrew&.api_delay_hours
      return unless threshold

      delay_hours = Homebrew::API.cached_packages_delay_hours
      return if delay_hours.nil? || delay_hours < threshold

      out.puts <<~EOS
        Package metadata was #{delay_hours} hours old at the last API refresh.
        A proxy or mirror may be delaying updates. A cooldown this long can leave
        your system exposed for #{delay_hours} more hours after Homebrew publishes a zero-day fix
        for an installed package.
      EOS
    end

    sig { params(out: T.any(File, StringIO, IO)).void }
    def homebrew_config(out = $stdout)
      out.puts "HOMEBREW_VERSION: #{HOMEBREW_VERSION}"
      out.puts "ORIGIN: #{origin}"
      out.puts "HEAD: #{head}"
      out.puts "Last commit: #{last_commit}"
      out.puts "Branch: #{branch}"
    end

    sig { params(out: T.any(File, StringIO, IO)).void }
    def homebrew_env_config(out = $stdout)
      out.puts "HOMEBREW_PREFIX: #{HOMEBREW_PREFIX}"
      repository = HOMEBREW_REPOSITORY
      cellar = HOMEBREW_CELLAR
      out.puts "HOMEBREW_REPOSITORY: #{repository}" if repository.to_s != Homebrew::DEFAULT_REPOSITORY.to_s
      out.puts "HOMEBREW_CELLAR: #{cellar}" if cellar.to_s != Homebrew::DEFAULT_CELLAR.to_s

      Homebrew::EnvConfig.non_default_variables.each do |env|
        env_symbol = env.to_sym
        hash = Homebrew::EnvConfig::ENVS.fetch(env_symbol)
        value = Homebrew::EnvConfig.public_send(Homebrew::EnvConfig.env_method_name(env_symbol, hash))

        if hash[:boolean]
          setting = value ? "set" : "false"
          out.puts "#{env}: #{setting}"
          next
        end

        next unless value

        if ENV.sensitive?(env)
          out.puts "#{env}: set"
        else
          out.puts "#{env}: #{value}"
        end
      end
      out.puts "Homebrew Ruby: #{describe_homebrew_ruby}"
    end

    sig { params(out: T.any(File, StringIO, IO)).void }
    def host_software_config(out = $stdout)
      out.puts "Clang: #{describe_clang}"
      out.puts "Git: #{describe_git}"
      out.puts "Curl: #{describe_curl}"
    end

    sig { params(out: T.any(File, StringIO, IO)).void }
    def hardware_config(out = $stdout)
      hardware = self.hardware
      out.puts hardware if hardware
    end

    sig { returns(T::Array[Symbol]) }
    def config_sections
      [:homebrew_config, :core_tap_config, :homebrew_env_config, :hardware_config, :host_software_config]
    end

    sig { params(out: T.any(File, StringIO, IO)).void }
    def dump_verbose_config(out = $stdout)
      # Most sections shell out for their values (Git, compilers, curl,
      # etc.), so render them concurrently and print them in order.
      sections = Utils.parallel_map(config_sections) do |section|
        io = StringIO.new
        public_send(section, io)
        io.string
      end
      sections.each { |section| out.print section }
    end
  end
end

require "extend/os/system_config"
