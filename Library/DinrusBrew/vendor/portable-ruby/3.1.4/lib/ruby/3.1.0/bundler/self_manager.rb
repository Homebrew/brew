# frozen_string_literal: true

module Bundler
  #
  # This class handles installing and switching to the version of bundler needed
  # by an application.
  #
  class SelfManager
    def restart_with_locked_bundler_if_needed
      return unless needs_switching? && installed?

      restart_with(lockfile_version)
    end

    def install_locked_bundler_and_restart_with_it_if_needed
      return unless needs_switching?

      Bundler.ui.info \
        "Bundler #{current_version} is running, but your lockfile was generated with #{lockfile_version}. " \
        "Installing Bundler #{lockfile_version} and restarting using that version."

      install_and_restart_with(lockfile_version)
    end

    def update_bundler_and_restart_with_it_if_needed(target)
      return unless autoswitching_applies?

      spec = resolve_update_version_from(target)
      return unless spec

      version = spec.version

      Bundler.ui.info "Updating bundler to #{version}."

      install(spec)

      restart_with(version)
    end

    private

    def install_and_restart_with(version)
      requirement = Gem::Requirement.new(version)
      spec = find_latest_matching_spec(requirement)

      if spec.nil?
        Bundler.ui.warn "Your lockfile is locked to a version of bundler (#{lockfile_version}) that doesn't exist at https://rubygems.org/. Going on using #{current_version}"
        return
      end

      install(spec)
    rescue StandardError => e
      Bundler.ui.trace e
      Bundler.ui.warn "There was an error installing the locked bundler version (#{lockfile_version}), rerun with the `--verbose` flag for more details. Going on using bundler #{current_version}."
    else
      restart_with(version)
    end

    def install(spec)
      spec.source.install(spec)
    end

    def restart_with(version)
      configured_gem_home = ENV["GEM_HOME"]
      configured_gem_path = ENV["GEM_PATH"]

      cmd = [$PROGRAM_NAME, *ARGV]
      cmd.unshift(Gem.ruby) unless File.executable?($PROGRAM_NAME)

      Bundler.with_original_env do
        Kernel.exec(
          { "GEM_HOME" => configured_gem_home, "GEM_PATH" => configured_gem_path, "BUNDLER_VERSION" => version.to_s },
          *cmd
        )
      end
    end

    def needs_switching?
      autoswitching_applies? &&
        released?(lockfile_version) &&
        !running?(lockfile_version) &&
        !updating?
    end

    def autoswitching_applies?
      ENV["BUNDLER_VERSION"].nil? &&
        Bundler.rubygems.supports_bundler_trampolining? &&
        SharedHelpers.in_bundle? &&
        lockfile_version
    end

    def resolve_update_version_from(target)
      requirement = Gem::Requirement.new(target)
      update_candidate = find_latest_matching_spec(requirement)

      if update_candidate.nil?
        raise InvalidOption, "The `bundle update --bundler` target version (#{target}) does not exist"
      end

      resolved_version = update_candidate.version
      needs_update = requirement.specific? ? !running?(resolved_version) : running_older_than?(resolved_version)

      return unless needs_update

      update_candidate
    end

    def local_specs
      @local_specs ||= Bundler::Source::Rubygems.new("allow_local" => true).specs.select {|spec| spec.name == "bundler" }
    end

    def remote_specs
      @remote_specs ||= begin
        source = Bundler::Source::Rubygems.new("remotes" => "https://rubygems.org")
        source.remote!
        source.add_dependency_names("bundler")
        source.specs
      end
    end

    def find_latest_matching_spec(requirement)
      local_result = find_latest_matching_spec_from_collection(local_specs, requirement)
      return local_result if local_result && requirement.specific?

      remote_result = find_latest_matching_spec_from_collection(remote_specs, requirement)
      return remote_result if local_result.nil?

      [local_result, remote_result].max
    end

    def find_latest_matching_spec_from_collection(specs, requirement)
      specs.sort.reverse_each.find {|spec| requirement.satisfied_by?(spec.version) }
    end

    def running?(version)
      version == current_version
    end

    def running_older_than?(version)
      current_version < version
    end

    def released?(version)
      !version.to_s.end_with?(".dev")
    end

    def updating?
      "update".start_with?(ARGV.first || " ") && ARGV[1..-1].any? {|a| a.start_with?("--bundler") }
    end

    def installed?
      Bundler.configure

      Bundler.rubygems.find_bundler(lockfile_version.to_s)
    end

    def current_version
      @current_version ||= Gem::Version.new(Bundler::VERSION)
    end

    def lockfile_version
      return @lockfile_version if defined?(@lockfile_version)

      parsed_version = Bundler::LockfileParser.bundled_with
      @lockfile_version = parsed_version ? Gem::Version.new(parsed_version) : nil
    end
  end
end
