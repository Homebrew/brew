# typed: true
# frozen_string_literal: true

module Utils
  # Helper functions for formula and cask info.
  module Info
    def self.decorate_dependencies(dependencies)
      deps_status = dependencies.map do |dep|
        if dep.satisfied?([])
          pretty_installed(dep_display_s(dep))
        else
          pretty_uninstalled(dep_display_s(dep))
        end
      end
      deps_status.join(", ")
    end

    def self.dep_display_s(dep)
      return dep.name if dep.option_tags.empty?

      "#{dep.name} #{dep.option_tags.map { |o| "--#{o}" }.join(" ")}"
    end
  end
end
