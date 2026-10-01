# typed: strict
# frozen_string_literal: true

require "system_command"
require "utils/curl"
require "yaml"

module Cask
  # Discovers the appcast of an app bundle, for use in a cask `livecheck` block.
  #
  # Checks for a Sparkle `SUFeedURL` and Electron Builder update metadata.
  module Appcast
    extend SystemCommand::Mixin

    class Result < T::Struct
      const :url, String
      const :strategy, Symbol
    end

    sig { params(app: Pathname).returns(T.nilable(Result)) }
    def self.find(app)
      find_sparkle(app) || find_electron_builder(app)
    end

    sig { params(app: Pathname).returns(T.nilable(Result)) }
    def self.find_sparkle(app)
      info_plist = app/"Contents/Info.plist"
      return unless info_plist.file?

      # `PlistBuddy` rather than `Plist.parse_xml` to also handle binary plists.
      result = system_command "/usr/libexec/PlistBuddy",
                              args:         ["-c", "Print SUFeedURL", info_plist],
                              print_stderr: false
      return unless result.success?

      url = result.stdout.lines.first&.strip
      return if url.blank?
      return unless url_exist?(url)

      Result.new(url:, strategy: :sparkle)
    end
    private_class_method :find_sparkle

    sig { params(app: Pathname).returns(T.nilable(Result)) }
    def self.find_electron_builder(app)
      appcast_file = app/"Contents/Resources/app-update.yml"
      return unless appcast_file.exist?

      components = begin
        YAML.load_file(appcast_file, symbolize_names: true)
      rescue Psych::Exception
        nil
      end
      return unless components.is_a?(Hash)

      components = components.compact

      # Electron Builder names the manifest after the update channel, but a cask
      # usually wants the stable feed, so always probe that first.
      channel = components[:channel]
      manifests = ["latest-mac.yml"]
      manifests << "#{channel}-mac.yml" if channel.present? && channel != "latest"

      candidates = manifests.flat_map do |manifest|
        [
          "#{components[:url]}/#{manifest}",
          "#{components[:url]}/updates/latest/mac/#{manifest}",
          "https://github.com/#{components[:owner]}/#{components[:repo]}/releases/latest/download/#{manifest}",
          "https://#{components[:bucket]}.s3.amazonaws.com/#{manifest}",
          "https://#{components[:bucket]}.s3.amazonaws.com/#{components[:path]}/#{manifest}",
          "https://s3-#{components[:region]}.amazonaws.com/#{components[:bucket]}/#{components[:path]}/#{manifest}",
          "https://s3.amazonaws.com/#{components[:bucket]}/#{components[:path]}/#{manifest}",
          "https://#{components[:name]}.#{components[:region]}.digitaloceanspaces.com/#{manifest}",
          "https://#{components[:name]}.#{components[:region]}.digitaloceanspaces.com/#{components[:path]}/#{manifest}",
          "#{components[:endpoint]}/#{components[:bucket]}/#{components[:path]}/#{manifest}",
        ]
      end

      possible_appcasts = candidates.filter_map do |url|
        # Absent components leave relative paths and empty hostnames behind.
        next unless url.start_with?("http://", "https://")
        next if url.include?("///") || url.include?("//.")

        url.gsub(%r{(?<!:)/{2,}}, "/")
      end.uniq

      url = possible_appcasts.find { |candidate| url_exist?(candidate) }
      return if url.nil?

      Result.new(url:, strategy: :electron_builder)
    end
    private_class_method :find_electron_builder

    sig { params(url: String).returns(T::Boolean) }
    def self.url_exist?(url)
      # A feed URL comes from the app bundle, so refuse anything that is not
      # HTTP(S) and pass it after `--` so cURL cannot read it as an option.
      return false unless url.start_with?("http://", "https://")

      # cURL's default `--connect-timeout` can be up to two minutes and it sets
      # no `--max-time` at all, so bound both: discovery probes several URLs in
      # sequence, including automatically from `brew create --cask`.
      ::Utils::Curl.curl_output(
        "--location", "--fail", "--silent", "--output", File::NULL, "--", url,
        connect_timeout: 10, max_time: 15, timeout: 20, retries: 0
      ).success?
    rescue Timeout::Error
      false
    end
    private_class_method :url_exist?
  end
end
