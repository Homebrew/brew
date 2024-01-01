# typed: true
# frozen_string_literal: true

require "json"

module Cask
  #
  # @api private
  class Info
    def self.get_info(cask)
      require "cask/installer"

      output = +"#{title_info(cask)}\n"
      output << "#{Formatter.url(cask.homepage)}\n" if cask.homepage
      deprecate_disable = DeprecateDisable.message(cask)
      output << "#{deprecate_disable.capitalize}\n" if deprecate_disable
      output << installation_info(cask)
      repo = repo_info(cask)
      output << "#{repo}\n" if repo
      output << name_info(cask)
      output << desc_info(cask)
      language = language_info(cask)
      output << language if language
      output << "#{artifact_info(cask)}\n"
      caveats = Installer.caveats(cask)
      output << caveats if caveats
      output
    end

    def self.info(cask)
      puts get_info(cask)
      ::Utils::Analytics.cask_output(cask, args: Homebrew::CLI::Args.new)
    end

    def self.title_info(cask)
      title = "#{oh1_title(cask.token)}: #{cask.version}"
      title += " (auto_updates)" if cask.auto_updates
      title
    end

    def self.installation_info(cask)
      return "Not installed\n" unless cask.installed?

      versioned_staged_path = cask.caskroom_path.join(cask.installed_version)
      path_details = if versioned_staged_path.exist?
        versioned_staged_path.abv
      else
        Formatter.error("does not exist")
      end

      "#{versioned_staged_path} (#{path_details})\n"
    end

    def self.name_info(cask)
      <<~EOS
        #{ohai_title((cask.name.size > 1) ? "Names" : "Name")}
        #{cask.name.empty? ? Formatter.error("None") : cask.name.join("\n")}
      EOS
    end

    def self.desc_info(cask)
      <<~EOS
        #{ohai_title("Description")}
        #{cask.desc.nil? ? Formatter.error("None") : cask.desc}
      EOS
    end

    def self.language_info(cask)
      return if cask.languages.empty?

      <<~EOS
        #{ohai_title("Languages")}
        #{cask.languages.join(", ")}
      EOS
    end

    def self.repo_info(cask)
      return if cask.tap.nil?

      url = if cask.tap.custom_remote? && !cask.tap.remote.nil?
        cask.tap.remote
      else
        "#{cask.tap.default_remote}/blob/HEAD/#{cask.tap.relative_cask_path(cask.token)}"
      end

      "From: #{Formatter.url(url)}"
    end

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
