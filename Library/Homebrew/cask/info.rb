# typed: strict
# frozen_string_literal: true

require "json"
require "cmd/info"
require "cask/cask_loader"
require "utils/output"
require "utils/info_display"

module Cask
  class Info
    extend ::Utils::Output::Mixin

    sig { params(cask: Cask, verbose: T::Boolean).returns(String) }
    def self.get_info(cask, verbose: false)
      require "cask/installer"

      installed = cask.installed?
      outdated = installed && cask.outdated?
      output = "#{::Utils::InfoDisplay.package_summary(
        formula_or_cask:     cask,
        title:               ::Utils::InfoDisplay::Title.new(
          name:              cask.token,
          display_names:     cask.name,
          version:           cask.version.to_s,
          installed_version: (cask.installed_version.presence if outdated),
          installed:,
          outdated:,
          auto_updates:      cask.auto_updates == true,
        ),
        installation_status: [installation_info(cask, installed:)],
        source_url:          repo_url(cask),
        installed_versions:  installed_section_rows(cask),
        verbose:,
        aliases:             cask.aliases,
      )}\n"
      deps = deps_info(cask, mark_uninstalled: installed)
      output << deps if deps
      require "cask_dependent"
      requirements = CaskDependent.new(cask).requirements.grep_v(CaskDependent::Requirement)
      if requirements.present?
        requirements_section = ::Utils::InfoDisplay.requirements_section(
          requirements, omit_macos_linux: !cask.supports_linux?
        )
        output << "#{requirements_section}\n" if requirements_section
      end
      language = language_info(cask)
      output << language if language
      artifacts = artifact_info(cask)
      output << "#{artifacts}\n" if artifacts
      if verbose
        binaries = cask.artifacts.grep(Artifact::Binary).map { |binary| binary.target.basename.to_s }
        output << "#{::Utils::InfoDisplay.binaries_section(binaries).chomp}\n" if binaries.present?
      end
      caveats = Installer.caveats(cask)
      output << caveats if caveats
      output
    end

    sig { params(cask: Cask, args: Homebrew::Cmd::Info::Args).void }
    def self.info(cask, args:)
      puts get_info(cask, verbose: args.verbose?)

      return unless cask.tap&.core_cask_tap?

      require "utils/analytics"
      ::Utils::Analytics.cask_output(cask, args:)
    end

    sig { params(cask: Cask, installed: T::Boolean).returns(String) }
    def self.installation_info(cask, installed:)
      return "Not installed" unless installed
      return "No installed version" unless cask.installed_version.present?

      ::Utils::InfoDisplay.installation_status(Tab.for_cask(cask))
    end

    sig { params(cask: Cask).returns(T::Array[::Utils::InfoDisplay::InstalledVersion]) }
    def self.installed_section_rows(cask)
      base_token = cask.token.split("@", 2).fetch(0)
      matching_token = ->(token) { token == base_token || token.start_with?("#{base_token}@") }
      tokens = Caskroom.tokens
      renamed_tokens = (tokens.empty? ? [] : Tap.to_a).flat_map do |tap|
        (tap.cask_renames.keys | tap.tap_migrations.keys).intersection(tokens).select do |token|
          resolved = CaskLoader.tap_cask_token_type("#{tap}/#{token}", warn: false)
          resolved && matching_token.call(resolved.first)
        end
      end
      related_tokens = tokens.select { |token| matching_token.call(token) || renamed_tokens.include?(token) }
      related_casks = [*Caskroom.casks(tokens: related_tokens), cask].uniq(&:token).select do |other|
        other.token == base_token || other.token.start_with?("#{base_token}@")
      end
      related_casks.sort_by(&:full_name).filter_map do |installed_cask|
        installed_version = installed_cask.installed_version
        next unless installed_version.present?

        versioned_staged_path = installed_cask.caskroom_path.join(installed_version)
        path_exists = versioned_staged_path.exist?
        size = if path_exists
          path_details = versioned_staged_path.children.sum(&:disk_usage)
          "(#{Formatter.disk_usage_readable(path_details)})"
        else
          ""
        end
        details = path_exists ? ["Caskroom: #{versioned_staged_path}"] : []
        if (tab = Tab.for_cask(installed_cask)).tabfile&.exist?
          details << tab.to_s
        end

        outdated = installed_cask.outdated?
        name = pretty_install_status(installed_cask.full_name, installed: true, outdated:)
        version = installed_version
        latest = installed_cask.version.to_s
        version = "#{version} → #{latest}" if outdated && latest != version
        ::Utils::InfoDisplay::InstalledVersion.new(
          name:,
          version:,
          size:,
          linked: false,
          details:,
          warning: ("#{versioned_staged_path} (#{Formatter.error("does not exist")})" unless path_exists),
        )
      end
    end

    sig { params(cask: Cask, mark_uninstalled: T::Boolean).returns(T.nilable(String)) }
    def self.deps_info(cask, mark_uninstalled: true)
      depends_on = cask.depends_on

      formula_deps = Array(depends_on[:formula]).map do |dep|
        name = dep.to_s
        decorate_dependency(
          name,
          installed:        Formula.rack_installed?(name),
          mark_uninstalled:,
        )
      end

      cask_deps = Array(depends_on[:cask]).map do |dep|
        name = dep.to_s
        decorate_dependency(
          "#{name} (cask)",
          installed:        (Caskroom.path/name).directory?,
          mark_uninstalled:,
        )
      end

      all_deps = formula_deps + cask_deps
      return if all_deps.empty?

      formula_dependencies = T.let(Set.new, T::Set[String])
      cask_dependencies = T.let(Set.new, T::Set[String])
      ::Utils::InfoDisplay.collect_cask_dependency_names(cask, formula_dependencies, cask_dependencies,
                                                         Set[cask.token])
      recursive_count = formula_dependencies.count + cask_dependencies.count
      lines = ["Required (#{all_deps.count}): #{all_deps.join(", ")}"]
      unless recursive_count.zero?
        installed_count = formula_dependencies.count do |name|
          Formula.rack_installed?(name)
        end + cask_dependencies.count do |name|
          (Caskroom.path/name).directory?
        end
        lines << ::Utils::InfoDisplay.recursive_runtime_line(installed_count, recursive_count)
      end

      "#{::Utils::InfoDisplay.section("Dependencies", lines)}\n"
    end

    sig { params(dep: String, installed: T::Boolean, mark_uninstalled: T::Boolean).returns(String) }
    def self.decorate_dependency(dep, installed:, mark_uninstalled: true)
      pretty_install_status(dep, installed:, mark_uninstalled:)
    end

    sig { params(cask: Cask).returns(T.nilable(String)) }
    def self.language_info(cask)
      return if cask.languages.empty?

      <<~EOS
        #{ohai_title("Languages")}
        #{cask.languages.join(", ")}
      EOS
    end

    sig { params(cask: Cask).returns(T.nilable(String)) }
    def self.repo_url(cask)
      return unless (tap = cask.tap)

      if tap.custom_remote? && !tap.remote.nil?
        tap.remote
      else
        "#{tap.default_remote}/blob/HEAD/#{tap.relative_cask_path(cask.token)}"
      end
    end

    sig { params(cask: Cask).returns(T.nilable(String)) }
    def self.artifact_info(cask)
      groups = T.let({}, T::Hash[String, T::Array[String]])
      cask.artifacts.each do |artifact|
        next unless artifact.respond_to?(:install_phase)
        next unless DSL::ORDINARY_ARTIFACT_CLASSES.include?(artifact.class)
        next if artifact.is_a?(Artifact::Binary)

        heading, detail = case artifact
        when Artifact::App, Artifact::AppImage
          ["Apps", artifact.summarize]
        when Artifact::Font
          ["Fonts", artifact.summarize]
        when Artifact::Manpage
          ["Manpages", artifact.summarize]
        when Artifact::AudioUnitPlugin, Artifact::Colorpicker, Artifact::InternetPlugin, Artifact::Qlplugin,
             Artifact::VstPlugin, Artifact::Vst3Plugin
          ["Plugins", artifact.to_s]
        else
          ["Artifacts", artifact.to_s]
        end
        (groups[heading] ||= []) << detail
      end
      return if groups.empty?

      %w[Apps Fonts Manpages Plugins Artifacts].filter_map do |heading|
        next unless (artifacts = groups[heading])

        [ohai_title(heading), *artifacts].join("\n")
      end.join("\n")
    end
  end
end
