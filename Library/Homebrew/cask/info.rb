# typed: strict
# frozen_string_literal: true

require "json"
require "cmd/info"
require "utils/output"

module Cask
  class Info
    extend ::Utils::Output::Mixin

    sig { params(cask: Cask).returns(String) }
    def self.get_info(cask)
      require "cask/installer"

      installed = cask.installed?
      output = "#{title_info(cask, installed:)}\n"
      output << "#{cask.desc}\n" if cask.desc
      output << "#{Formatter.url(cask.homepage)}\n" if cask.homepage
      deprecate_disable = DeprecateDisable.message(cask)
      if deprecate_disable.present?
        deprecate_disable.tap { |message| message[0] = message[0].upcase }
        output << "#{deprecate_disable}\n"
      end
      output << "#{installation_info(cask, installed:)}\n"
      repo = repo_info(cask)
      output << "#{repo}\n" if repo
      deps = deps_info(cask)
      output << deps if deps
      requirements = requirements_info(cask)
      output << requirements if requirements
      language = language_info(cask)
      output << language if language
      output << "#{artifact_info(cask)}\n"
      caveats = Installer.caveats(cask)
      output << caveats if caveats
      output
    end

    sig { params(cask: Cask, args: Homebrew::Cmd::Info::Args).void }
    def self.info(cask, args:)
      puts get_info(cask)

      return unless cask.tap&.core_cask_tap?

      require "utils/analytics"
      ::Utils::Analytics.cask_output(cask, args:)
    end

    sig { params(cask: Cask, installed: T::Boolean).returns(String) }
    def self.title_info(cask, installed:)
      name_with_status = if installed
        pretty_installed(cask.token)
      else
        pretty_uninstalled(cask.token)
      end
      title = oh1_title(name_with_status).to_s
      title += " (#{cask.name.join(", ")})" unless cask.name.empty?
      title += ": #{cask.version}"
      title += " (auto_updates)" if cask.auto_updates
      title
    end

    sig { params(cask: Cask, installed: T::Boolean).returns(String) }
    def self.installation_info(cask, installed:)
      return "Not installed" unless installed
      return "No installed version" unless (installed_version = cask.installed_version).present?

      versioned_staged_path = cask.caskroom_path.join(installed_version)
      tab = Tab.for_cask(cask)

      unless versioned_staged_path.exist?
        return "#{Homebrew::Cmd::Info.installation_status(tab)}\n" \
               "#{versioned_staged_path} (#{Formatter.error("does not exist")})\n"
      end

      path_details = versioned_staged_path.children.sum(&:disk_usage)

      info = [Homebrew::Cmd::Info.installation_status(tab)]
      info << "#{versioned_staged_path} (#{Formatter.disk_usage_readable(path_details)})"
      info << "  #{tab}" if tab.tabfile&.exist?
      info.join("\n")
    end

    sig { params(cask: Cask).returns(T.nilable(String)) }
    def self.deps_info(cask)
      depends_on = cask.depends_on

      formula_deps = Array(depends_on[:formula]).map do |dep|
        name = dep.to_s
        rack = HOMEBREW_CELLAR/name.split("/").last
        decorate_dependency(name, installed: rack.directory? && !rack.subdirs.empty?)
      end

      cask_deps = Array(depends_on[:cask]).map do |dep|
        name = dep.to_s
        decorate_dependency("#{name} (cask)", installed: (Caskroom.path/name).directory?)
      end

      all_deps = formula_deps + cask_deps
      return if all_deps.empty?

      formula_dependencies = T.let(Set.new, T::Set[String])
      cask_dependencies = T.let(Set.new, T::Set[String])
      Homebrew::Cmd::Info.collect_cask_dependency_names(cask, formula_dependencies, cask_dependencies,
                                                        Set[cask.token])
      recursive_count = formula_dependencies.count + cask_dependencies.count
      lines = T.let(
        [ohai_title("Dependencies").to_s, "Required (#{all_deps.count}): #{all_deps.join(", ")}"],
        T::Array[String],
      )
      unless recursive_count.zero?
        installed_count = formula_dependencies.count do |name|
          rack = HOMEBREW_CELLAR/name.split("/").last
          rack.directory? && !rack.subdirs.empty?
        end + cask_dependencies.count do |name|
          (Caskroom.path/name).directory?
        end
        lines << "Recursive Runtime (#{recursive_count}): " \
                 "#{Homebrew::Cmd::Info.dependency_status_counts(installed_count, recursive_count)}"
      end

      "#{lines.join("\n")}\n"
    end

    sig { params(dep: String, installed: T::Boolean).returns(String) }
    def self.decorate_dependency(dep, installed:)
      installed ? pretty_installed(dep) : pretty_uninstalled(dep)
    end

    sig { params(cask: Cask).returns(T.nilable(String)) }
    def self.requirements_info(cask)
      require "cask_dependent"

      requirements = CaskDependent.new(cask).requirements.grep_v(CaskDependent::Requirement)
      return if requirements.empty?

      supports_linux = cask.supports_linux?
      output = "#{ohai_title("Requirements")}\n"
      %w[build required recommended optional].each do |type|
        reqs = case type
        when "build"
          requirements.select(&:build?)
        when "required"
          requirements.select(&:required?)
        when "recommended"
          requirements.select(&:recommended?)
        when "optional"
          requirements.select(&:optional?)
        else
          []
        end
        next if reqs.empty?

        output << "#{type.capitalize}: #{reqs.map do |requirement|
          requirement_s = if requirement.is_a?(MacOSRequirement) && !supports_linux
            requirement.display_s.delete_suffix(" (or Linux)")
          else
            requirement.display_s
          end
          installed = requirement.satisfied?
          installed ? pretty_installed(requirement_s) : pretty_uninstalled(requirement_s)
        end.join(", ")}\n"
      end
      output
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
    def self.repo_info(cask)
      return unless (tap = cask.tap)

      url = if tap.custom_remote? && !tap.remote.nil?
        tap.remote
      else
        "#{tap.default_remote}/blob/HEAD/#{tap.relative_cask_path(cask.token)}"
      end

      "From: #{Formatter.url(url)}"
    end

    sig { params(cask: Cask).returns(String) }
    def self.artifact_info(cask)
      artifact_output = ohai_title("Artifacts").dup
      cask.artifacts.each do |artifact|
        next unless artifact.respond_to?(:install_phase)
        next unless DSL::ORDINARY_ARTIFACT_CLASSES.include?(artifact.class)

        artifact_output << "\n" << artifact.to_s
      end
      artifact_output.freeze
    end
  end
end
