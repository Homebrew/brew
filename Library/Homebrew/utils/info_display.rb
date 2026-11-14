# typed: strict
# frozen_string_literal: true

require "utils/output"
require "deprecate_disable"
require "simulate_system"

module Utils
  # Shared presentation helpers for formula and cask information.
  module InfoDisplay
    extend Utils::Output::Mixin

    class InstalledVersion < T::Struct
      const :name, String
      const :version, String
      const :size, String
      const :linked, T::Boolean
      const :details, T::Array[String]
      const :warning, T.nilable(String), default: nil
    end

    class Title < T::Struct
      const :name, String
      const :display_names, T::Array[String], default: []
      const :version, T.nilable(String), default: nil
      const :installed_version, T.nilable(String), default: nil
      const :installed, T::Boolean, default: false
      const :outdated, T::Boolean, default: false
      const :warning, T::Boolean, default: false
      const :removed, T::Boolean, default: false
      const :stable, T::Boolean, default: false
      const :bottled, T::Boolean, default: false
      const :head, T::Boolean, default: false
      const :keg_only, T::Boolean, default: false
      const :auto_updates, T::Boolean, default: false
    end

    sig {
      params(title: Title, deprecated: T::Boolean, disabled: T::Boolean, can_install: T::Boolean).returns(String)
    }
    def self.package_title(title, deprecated: false, disabled: false, can_install: true)
      name = pretty_install_status(
        title.name, installed: title.installed, outdated: title.outdated, warning: title.warning,
                    removed: title.removed, deprecated:, disabled:, can_install:, bold: true
      )
      heading = oh1_title(name).to_s
      heading += " (#{title.display_names.join(", ")})" if title.display_names.any?
      versions = []
      if (title_version = title.version)
        version = title.stable ? "stable #{title_version}" : title_version
        version += " (bottled)" if title.bottled
        versions << version
      end
      versions << "HEAD" if title.head
      if title.outdated && title.installed_version && versions.any?
        versions[0] = "#{title.installed_version} → #{versions[0]}"
      end
      heading += ": #{versions.join(", ")}"
      heading += " [keg-only]" if title.keg_only
      heading += " (auto_updates)" if title.auto_updates
      heading
    end

    sig { params(formula_or_cask: T.any(Formula, Cask::Cask)).returns(T::Array[String]) }
    def self.metadata_lines(formula_or_cask)
      return [] unless $stdout.tty?

      case formula_or_cask
      when Formula
        formula_metadata_lines(formula_or_cask)
      when Cask::Cask
        if formula_or_cask.pinned?
          pinned = "Pinned: #{formula_or_cask.pinned_version}"
          if (pinned_time = pin_path_mtime(formula_or_cask.pin_path))
            pinned << " on #{formatted_time(pinned_time)}"
          end
          [pinned]
        else
          []
        end
      else
        T.absurd(formula_or_cask)
      end
    end

    sig { params(tab: T.any(Tab, Cask::Tab)).returns(String) }
    def self.installation_status(tab)
      tab.installed_on_request ? "Installed (on request)" : "Installed (as dependency)"
    end

    sig { params(tab: T.any(Tab, Cask::Tab)).returns(String) }
    def self.installation_reason(tab)
      return "-" unless tab.installed_on_request_present?

      tab.installed_on_request ? "on request" : "dependency"
    end

    sig { params(version: String, tab: T.any(Tab, Cask::Tab)).returns(String) }
    def self.installation_summary(version, tab)
      reason = installation_reason(tab)

      "Installed: #{version}#{" (#{reason})" if reason != "-"}"
    end

    sig {
      params(
        title:               Title,
        formula_or_cask:     T.any(Formula, Cask::Cask),
        installation_status: T::Array[String],
        source_url:          T.nilable(String),
        installed_versions:  T::Array[InstalledVersion],
        verbose:             T::Boolean,
        tap:                 T.nilable(Tap),
        license:             T.nilable(T.any(String, Symbol, T::Hash[T.nilable(T.any(Symbol, String)), T.untyped])),
        shadowed_by:         T.nilable(String),
        aliases:             T::Array[String],
        old_names:           T::Array[String],
        conflicts:           T::Array[String],
      ).returns(String)
    }
    def self.package_summary(
      title:,
      formula_or_cask:,
      installation_status:,
      source_url:,
      installed_versions:,
      verbose:,
      tap: nil,
      license: nil,
      shadowed_by: nil,
      aliases: [],
      old_names: [],
      conflicts: []
    )
      deprecation = DeprecateDisable.message(formula_or_cask)
      deprecation = deprecation.chomp.sub(/\A./, &:upcase) if deprecation.present?
      installed_title = if verbose && formula_or_cask.is_a?(Formula)
        "Installed Kegs and Versions"
      else
        "Installed Versions"
      end
      [
        package_title(title, deprecated: formula_or_cask.deprecated?, disabled: formula_or_cask.disabled?,
                             can_install: formula_or_cask.valid_platform? && !formula_or_cask.disabled?),
        (if shadowed_by && formula_or_cask.is_a?(Formula)
           Formatter.warning("`#{formula_or_cask.name}` shadows `#{shadowed_by}/#{formula_or_cask.name}`.",
                             label: "Warning")
        end),
        formula_or_cask.desc,
        (Formatter.url(formula_or_cask.homepage) if formula_or_cask.homepage),
        deprecation,
        ("Aliases: #{aliases.join(", ")}" if aliases.any?),
        ("Old Names: #{old_names.join(", ")}" if old_names.any?),
        ("Conflicts with:\n  #{conflicts.join("\n  ")}" if conflicts.any?),
        *installation_status,
        ("From: #{Formatter.url(source_url)}" if source_url),
        ("Tap: #{tap.name}" if tap && !tap.official?),
        ("License: #{SPDX.license_expression_to_string(license)}" if license.present?),
        *metadata_lines(formula_or_cask),
        installed_versions_section(installed_versions, title: installed_title, show_details: verbose),
      ].compact.join("\n")
    end

    sig {
      params(
        rows:         T::Array[InstalledVersion],
        title:        String,
        show_details: T::Boolean,
      ).returns(T.nilable(String))
    }
    def self.installed_versions_section(rows, title:, show_details:)
      return if rows.empty?

      name_width = rows.map { Tty.strip_ansi(it.name).length }.max || 0
      version_width = rows.map { it.version.length }.max || 0
      size_width = rows.map { it.size.length }.max || 0
      lines = rows.flat_map do |row|
        padded_name = row.name + (" " * (name_width - Tty.strip_ansi(row.name).length))
        padded_size = if row.linked
          " #{row.size.ljust(size_width)}"
        elsif row.size.empty?
          ""
        else
          " #{row.size}"
        end
        line = "#{padded_name} #{row.version.ljust(version_width)}#{padded_size}"
        line += " [Linked]" if row.linked
        row_lines = [line]
        row_lines << "  #{row.warning}" if row.warning
        row_lines.concat(row.details.map { |detail| "  #{detail}" }) if show_details
        row_lines
      end
      section(title, lines)
    end

    sig { params(title: String, lines: T::Array[String]).returns(String) }
    def self.section(title, lines)
      [ohai_title(title), *lines].join("\n")
    end

    sig {
      params(
        requirements:     T::Array[Requirement],
        omit_macos_linux: T::Boolean,
        mark_uninstalled: T::Boolean,
        bold:             T.nilable(T::Boolean),
      ).returns(T.nilable(String))
    }
    def self.requirements_section(requirements, omit_macos_linux: false, mark_uninstalled: true, bold: nil)
      return if requirements.empty?

      lines = %w[build required recommended optional].filter_map do |type|
        reqs = requirements.select { |requirement| requirement.public_send(:"#{type}?") }
        next if reqs.empty?

        formatted = reqs.map do |requirement|
          text = requirement.display_s
          text = text.delete_suffix(" (or Linux)") if omit_macos_linux && requirement.is_a?(MacOSRequirement)
          pretty_install_status(text, installed: requirement.satisfied?, mark_uninstalled:, bold:)
        end
        "#{type.capitalize}: #{formatted.join(", ")}"
      end
      section("Requirements", lines)
    end

    sig { params(binaries: T::Array[String], additional_text: T.nilable(String)).returns(String) }
    def self.binaries_section(binaries, additional_text: nil)
      formatted = [
        (Formatter.columns(binaries.sort.uniq) if binaries.present?),
        additional_text,
      ].compact.join("\n")
      section("Binaries", formatted.empty? ? [] : [formatted])
    end

    sig { params(requirement: Requirement).returns(T::Boolean) }
    def self.requirement_for_other_os?(requirement)
      return !Homebrew::SimulateSystem.simulating_or_running_on_macos? if requirement.instance_of?(MacOSRequirement)
      return !Homebrew::SimulateSystem.simulating_or_running_on_linux? if requirement.instance_of?(LinuxRequirement)

      false
    end

    sig { params(installed_count: Integer, total_count: Integer, mark_uninstalled: T::Boolean).returns(String) }
    def self.dependency_status_counts(installed_count, total_count, mark_uninstalled: true)
      missing_count = total_count - installed_count
      return "all installed #{Formatter.success("✔")}" if missing_count.zero?

      missing_status = mark_uninstalled ? "missing #{Formatter.error("✘")}" : "not installed"
      "#{installed_count} installed #{Formatter.success("✔")}, " \
        "#{missing_count} #{missing_status}"
    end

    sig { params(installed_count: Integer, total_count: Integer, mark_uninstalled: T::Boolean).returns(String) }
    def self.recursive_runtime_line(installed_count, total_count, mark_uninstalled: true)
      "Recursive Runtime (#{total_count}): " \
        "#{dependency_status_counts(installed_count, total_count, mark_uninstalled:)}"
    end

    sig { params(formula: Formula).returns(T::Array[String]) }
    def self.formula_metadata_lines(formula)
      metadata = T.let([], T::Array[String])
      if formula.pinned?
        pinned = "Pinned: #{formula.pinned_version}"
        if (pinned_time = pin_path_mtime(FormulaPin.new(formula).path))
          pinned << " on #{formatted_time(pinned_time)}"
        end
        metadata << pinned
      end

      if !formula.any_version_installed? && formula_installs_from_source?(formula)
        metadata << "Installs from source: yes"
      end
      metadata
    end

    sig { params(time: T.any(Integer, Time)).returns(String) }
    def self.formatted_time(time)
      time = Time.at(time) if time.is_a?(Integer)

      time.strftime("%Y-%m-%d at %H:%M:%S")
    end

    sig { params(pin_path: Pathname).returns(T.nilable(Time)) }
    def self.pin_path_mtime(pin_path)
      pin_path.lstat.mtime if pin_path.symlink? || pin_path.exist?
    rescue Errno::ENOENT
      nil
    end

    sig { params(formula: Formula).returns(T::Boolean) }
    def self.formula_installs_from_source?(formula)
      return false if formula.requirements.any? { |requirement| requirement_for_other_os?(requirement) }

      stable = formula.stable
      return true if stable.blank? && formula.head.present?
      return false if stable.blank?

      !stable.bottled? || !formula.pour_bottle?
    end

    sig {
      params(cask: Cask::Cask, formula_dependencies: T::Set[String], cask_dependencies: T::Set[String],
             visited_casks: T::Set[String]).void
    }
    def self.collect_cask_dependency_names(cask, formula_dependencies, cask_dependencies, visited_casks)
      cask.depends_on.formula.each do |name|
        dep_name = name.to_s
        formula_dependencies << dep_name
        rack = HOMEBREW_CELLAR/Utils.name_from_full_name(dep_name)
        next unless rack.directory?

        keg = Keg.from_rack(rack)
        next unless keg

        tab_deps = Tab.for_keg(keg).runtime_dependencies
        tab_deps&.each do |runtime_dep|
          dep_full_name = T.cast(runtime_dep, T::Hash[String, T.untyped])["full_name"]
          formula_dependencies << dep_full_name if dep_full_name
        end
      end

      cask.depends_on.cask.each do |name|
        token = name.to_s
        next if visited_casks.include?(token)

        cask_dependencies << token
        visited_casks << token
        begin
          dependency = Cask::CaskLoader.load(token)
          collect_cask_dependency_names(dependency, formula_dependencies, cask_dependencies, visited_casks)
        rescue Cask::CaskUnavailableError
          next
        end
      end
    end

    private_class_method :installed_versions_section, :formula_metadata_lines, :formatted_time, :pin_path_mtime
  end
end
