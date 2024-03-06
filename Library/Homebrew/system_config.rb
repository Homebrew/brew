# typed: true
# frozen_string_literal: true

require "hardware"
require "software_spec"
require "development_tools"
require "extend/ENV"
require "system_command"

# Helper module for querying information about the system configuration.
module SystemConfig
  class << self
    include SystemCommand::Mixin

    def clang
      @clang ||= if DevelopmentTools.installed?
        DevelopmentTools.clang_version
      else
        Version::NULL
      end
    end

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

    sig { returns(String) }
    def head
      homebrew_repo.head_ref || "(none)"
    end

    sig { returns(String) }
    def last_commit
      homebrew_repo.last_committed || "never"
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

    def describe_path(path)
      return "N/A" if path.nil?

      realpath = path.realpath
      if realpath == path
        path
      else
        "#{path} => #{realpath}"
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
      `uname -m`.chomp
    end

    sig { returns(String) }
    def describe_git
      return "N/A" unless Utils::Git.available?

      "#{Utils::Git.version} => #{Utils::Git.path}"
    end

    sig { returns(String) }
    def describe_curl
      out, = system_command(Utils::Curl.curl_executable, args: ["--version"], verbose: false)

      match_data = /^curl (?<curl_version>[\d.]+)/.match(out)
      if match_data
        "#{match_data[:curl_version]} => #{Utils::Curl.curl_path}"
      else
        "N/A"
      end
    end

    def dump_tap_config(tap, out = $stdout)
      case tap
      when CoreTap
        tap_name = "Core tap"
        json_file_name = "formula.jws.json"
      when CoreCaskTap
        tap_name = "Core cask tap"
        json_file_name = "cask.jws.json"
      else
        raise ArgumentError, "Unknown tap: #{tap}"
      end

      if tap.installed?
        out.puts "#{tap_name} origin: #{tap.remote}" if tap.remote != tap.default_remote
        out.puts "#{tap_name} HEAD: #{tap.git_head || "(none)"}"
        out.puts "#{tap_name} last commit: #{tap.git_last_commit || "never"}"
        out.puts "#{tap_name} branch: #{tap.git_branch || "(none)"}" if tap.git_branch != "master"
      end

      if (json_file = Homebrew::API::HOMEBREW_CACHE_API/json_file_name) && json_file.exist?
        out.puts "#{tap_name} JSON: #{json_file.mtime.utc.strftime("%d %b %H:%M UTC")}"
      elsif !tap.installed?
        out.puts "#{tap_name}: N/A"
      end
    end

    def core_tap_config(out = $stdout)
      dump_tap_config(CoreTap.instance, out)
    end

    def homebrew_config(out = $stdout)
      out.puts "HOMEBREW_VERSION: #{HOMEBREW_VERSION}"
      out.puts "ORIGIN: #{origin}"
      out.puts "HEAD: #{head}"
      out.puts "Last commit: #{last_commit}"
    end

    def homebrew_env_config(out = $stdout)
      out.puts "HOMEBREW_PREFIX: #{HOMEBREW_PREFIX}"
      {
        HOMEBREW_REPOSITORY: Homebrew::DEFAULT_REPOSITORY,
        HOMEBREW_CELLAR:     Homebrew::DEFAULT_CELLAR,
      }.freeze.each do |key, default|
        value = Object.const_get(key)
        out.puts "#{key}: #{value}" if value.to_s != default.to_s
      end

      Homebrew::EnvConfig::ENVS.each do |env, hash|
        method_name = Homebrew::EnvConfig.env_method_name(env, hash)

        if hash[:boolean]
          out.puts "#{env}: set" if Homebrew::EnvConfig.send(method_name)
          next
        end

        value = Homebrew::EnvConfig.send(method_name)
        next unless value
        next if (default = hash[:default].presence) && value.to_s == default.to_s

        if ENV.sensitive?(env)
          out.puts "#{env}: set"
        else
          out.puts "#{env}: #{value}"
        end
      end
      out.puts "Homebrew Ruby: #{describe_homebrew_ruby}"
    end

    def host_software_config(out = $stdout)
      out.puts "Clang: #{describe_clang}"
      out.puts "Git: #{describe_git}"
      out.puts "Curl: #{describe_curl}"
    end

    def dump_verbose_config(out = $stdout)
      homebrew_config(out)
      core_tap_config(out)
      homebrew_env_config(out)
      out.puts hardware if hardware
      host_software_config(out)
    end
    alias dump_generic_verbose_config dump_verbose_config
  end
end

require "extend/os/system_config"
