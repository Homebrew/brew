# typed: true
# frozen_string_literal: true

require "cask/artifact/relocated"

module Cask
  # @api private
  class List
    def self.list_casks(*casks, one: false, full_name: false, versions: false)
      output = if casks.any?
        casks.each do |cask|
          raise CaskNotInstalledError, cask unless cask.installed?
        end
      else
        Caskroom.casks
      end

      if one
        puts output.map(&:to_s)
      elsif full_name
        puts output.map(&:full_name).sort(&tap_and_name_comparison)
      elsif versions
        puts output.map(&method(:format_versioned))
      elsif !output.empty? && casks.any?
        output.map(&method(:list_artifacts))
      elsif !output.empty?
        puts Formatter.columns(output.map(&:to_s))
      end
    end

    def self.list_artifacts(cask)
      cask.artifacts.group_by(&:class).sort_by { |klass, _| klass.english_name }.each do |klass, artifacts|
        next if [Artifact::Uninstall, Artifact::Zap].include? klass

        ohai klass.english_name
        artifacts.each do |artifact|
          puts artifact.summarize_installed if artifact.respond_to?(:summarize_installed)
          next if artifact.respond_to?(:summarize_installed)

          puts artifact
        end
      end
    end

    def self.format_versioned(cask)
      "#{cask}#{cask.installed_version&.prepend(" ")}"
    end
  end
end
