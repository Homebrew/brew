# typed: strict
# frozen_string_literal: true

require "json"
require "cmd/info"

module Cask
  class Info
    sig { params(cask: Cask).returns(String) }
    def self.get_info(cask)
      require "cask/installer"

      output = "#{title_info(cask)}\n"
      output << "#{Formatter.url(cask.homepage)}\n" if cask.homepage
      deprecate_disable = DeprecateDisable.message(cask)
      if deprecate_disable.present?
        deprecate_disable.tap { |message| message[0] = message[0].upcase }
        output << "#{deprecate_disable}\n"
      end
      output << "#{installation_info(cask)}\n"
      repo = repo_info(cask)
      output << "#{repo}\n" if repo
      output << name_info(cask)
      output << desc_info(cask)
      deps = deps_info(cask)
      output << deps if deps
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

      require "utils/analytics"
      ::Utils::Analytics.cask_output(cask, args:)
    end

    sig { params(cask: Cask).returns(String) }
    def self.title_info(cask)
      title = "#{oh1_title(cask.token)}: #{cask.version}"
      title += " (auto_updates)" if cask.auto_updates
      title
    end

    sig { params(cask: Cask).returns(String) }
    def self.installation_info(cask)
      return "Not installed" unless cask.installed?
      return "No installed version" unless (installed_version = cask.installed_version).present?

      versioned_staged_path = cask.caskroom_path.join(installed_version)

      return "Installed\n#{versioned_staged_path} (#{Formatter.error("does not exist")})\n" unless versioned_staged_path.exist?

      path_details = versioned_staged_path.children.sum(&:disk_usage)

      tab = Tab.for_cask(cask)

      info = ["Installed"]
      info << "#{versioned_staged_path} (#{disk_usage_readable(path_details)})"
      info << "  #{tab}" if tab.tabfile&.exist?
      info.join("\n")
    end

    sig { params(cask: Cask).returns(String) }
    def self.name_info(cask)
      <<~EOS
        #{ohai_title((cask.name.size > 1) ? "Names" : "Name")}
        #{cask.name.empty? ? Formatter.error("None") : cask.name.join("\n")}
      EOS
    end

    sig { params(cask: Cask).returns(String) }
    def self.desc_info(cask)
      <<~EOS
        #{ohai_title("Description")}
        #{cask.desc.nil? ? Formatter.error("None") : cask.desc}
      EOS
    end

    sig { params(cask: Cask).returns(T.nilable(String)) }
    def self.deps_info(cask)
      depends_on = cask.depends_on

      formula_deps = Array(depends_on[:formula]).map(&:to_s)
      cask_deps = Array(depends_on[:cask]).map { |dep| "#{dep} (cask)" }

      all_deps = formula_deps + cask_deps
      return if all_deps.empty?

      <<~EOS
        #{ohai_title("Dependencies")}
        #{all_deps.join(", ")}
      EOS
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
      return if cask.tap.nil?

      url = if cask.tap.custom_remote? && !cask.tap.remote.nil?
        cask.tap.remote
      else
        "#{cask.tap.default_remote}/blob/HEAD/#{cask.tap.relative_cask_path(cask.token)}"
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
