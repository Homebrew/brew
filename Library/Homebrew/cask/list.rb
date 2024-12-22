# typed: strict
# frozen_string_literal: true

require "cask/artifact/relocated"

module Cask
  class List
    sig { params(casks: Cask, one: T::Boolean, full_name: T::Boolean, versions: T::Boolean).void }
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
        puts output.map { format_versioned(_1) }
      elsif !output.empty? && casks.any?
        output.map { list_artifacts(_1) }
      elsif !output.empty?
        puts Formatter.columns(output.map(&:to_s))
      end
    end

    sig { params(cask: Cask).void }
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

    sig { params(cask: Cask).returns(String) }
    def self.format_versioned(cask)
      "#{cask}#{cask.installed_version&.prepend(" ")}"
    end
  end
end
