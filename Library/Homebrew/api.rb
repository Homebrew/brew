# typed: strict
# frozen_string_literal: true

require "api/analytics"
require "api/cask"
require "api/formula"
require "api/internal"
require "api/formula_struct"
require "api/cask_struct"
require "base64"
require "utils/output"

module Homebrew
  # Helper functions for using Homebrew's formulae.brew.sh API.
  module API
    extend Utils::Output::Mixin

    extend Cachable

    HOMEBREW_CACHE_API = T.let((HOMEBREW_CACHE/"api").freeze, Pathname)
    HOMEBREW_CACHE_API_SOURCE = T.let((HOMEBREW_CACHE/"api-source").freeze, Pathname)
    DEFAULT_API_STALE_SECONDS = T.let(7 * 24 * 60 * 60, Integer) # 7 days

    sig { params(endpoint: String).returns(T::Hash[String, T.untyped]) }
    def self.fetch(endpoint)
      return cache[endpoint] if cache.present? && cache.key?(endpoint)

      api_url = "#{Homebrew::EnvConfig.api_domain}/#{endpoint}"
      output = Utils::Curl.curl_output("--fail", api_url)
      if !output.success? && Homebrew::EnvConfig.api_domain != HOMEBREW_API_DEFAULT_DOMAIN
        # Fall back to the default API domain and try again
        api_url = "#{HOMEBREW_API_DEFAULT_DOMAIN}/#{endpoint}"
        output = Utils::Curl.curl_output("--fail", api_url)
      end
      raise ArgumentError, "No file found at: #{Tty.underline}#{api_url}#{Tty.reset}" unless output.success?

      cache[endpoint] = JSON.parse(output.stdout, freeze: true)
    rescue JSON::ParserError
      raise ArgumentError, "Invalid JSON file: #{Tty.underline}#{api_url}#{Tty.reset}"
    end

    sig { params(target: Pathname, stale_seconds: T.nilable(Integer)).returns(T::Boolean) }
    def self.skip_download?(target:, stale_seconds:)
      return true if Homebrew.running_as_root_but_not_owned_by_root?
      return false if !target.exist? || target.empty?
      return true unless stale_seconds

      (Time.now - stale_seconds) < target.mtime
    end

    sig {
      params(
        endpoint:       String,
        target:         Pathname,
        stale_seconds:  T.nilable(Integer),
        download_queue: T.nilable(DownloadQueue),
      ).returns([T.any(T::Array[T.untyped], T::Hash[String, T.untyped]), T::Boolean])
    }
    def self.fetch_json_api_file(endpoint, target: HOMEBREW_CACHE_API/endpoint,
                                 stale_seconds: nil, download_queue: nil)
      # Lazy-load dependency.
      require "development_tools"

      retry_count = 0
      url = "#{Homebrew::EnvConfig.api_domain}/#{endpoint}"
      default_url = "#{HOMEBREW_API_DEFAULT_DOMAIN}/#{endpoint}"

      if Homebrew.running_as_root_but_not_owned_by_root? &&
         (!target.exist? || target.empty?)
        odie "Need to download #{url} but cannot as root! Run `brew update` without `sudo` first then try again."
      end

      curl_args = Utils::Curl.curl_args(retries: 0) + %W[
        --compressed
        --speed-limit #{ENV.fetch("HOMEBREW_CURL_SPEED_LIMIT")}
        --speed-time #{ENV.fetch("HOMEBREW_CURL_SPEED_TIME")}
      ]

      insecure_download = DevelopmentTools.ca_file_substitution_required? ||
                          DevelopmentTools.curl_substitution_required?
      skip_download = skip_download?(target:, stale_seconds:)

      if download_queue
        unless skip_download
          require "api/json_download"
          download = Homebrew::API::JSONDownload.new(endpoint, target:, stale_seconds:)
          download_queue.enqueue(download)
        end
        return [{}, false]
      end

      json_data = begin
        begin
          args = curl_args.dup
          args.prepend("--time-cond", target.to_s) if target.exist? && !target.empty?
          if insecure_download
            opoo DevelopmentTools.insecure_download_warning(endpoint)
            args.append("--insecure")
          end
          unless skip_download
            ohai "Downloading #{url}" if $stdout.tty? && !Context.current.quiet?
            # Disable retries here, we handle them ourselves below.
            Utils::Curl.curl_download(*args, url, to: target, retries: 0, show_error: false)
          end
        rescue ErrorDuringExecution
          if url == default_url
            raise unless target.exist?
            raise if target.empty?
          elsif retry_count.zero? || !target.exist? || target.empty?
            # Fall back to the default API domain and try again
            # This block will be executed only once, because we set `url` to `default_url`
            url = default_url
            target.unlink if target.exist? && target.empty?
            skip_download = false

            retry
          end

          opoo "#{target.basename}: update failed, falling back to cached version."
        end

        mtime = insecure_download ? Time.new(1970, 1, 1) : Time.now
        FileUtils.touch(target, mtime:) unless skip_download
        # Can use `target.read` again when/if https://github.com/sorbet/sorbet/pull/8999 is merged/released.
        JSON.parse(File.read(target, encoding: Encoding::UTF_8), freeze: true)
      rescue JSON::ParserError
        target.unlink
        retry_count += 1
        skip_download = false
        odie "Cannot download non-corrupt #{url}!" if retry_count > Homebrew::EnvConfig.curl_retries.to_i

        retry
      end

      if endpoint.end_with?(".jws.json")
        success, data = verify_and_parse_jws(json_data)
        unless success
          target.unlink
          odie <<~EOS
            Failed to verify integrity (#{data}) of:
              #{url}
            Potential MITM attempt detected. Please run `brew update` and try again.
          EOS
        end
        [data, !skip_download]
      else
        [json_data, !skip_download]
      end
    end

    sig {
      params(json:       T::Hash[String, T.untyped],
             bottle_tag: ::Utils::Bottles::Tag).returns(T::Hash[String, T.untyped])
    }
    def self.merge_variations(json, bottle_tag: T.unsafe(nil))
      return json unless json.key?("variations")

      bottle_tag ||= Homebrew::SimulateSystem.current_tag

      if (variation = json.dig("variations", bottle_tag.to_s).presence) ||
         (variation = json.dig("variations", bottle_tag.to_sym).presence)
        json = json.merge(variation)
      end

      json.except("variations")
    end

    sig { void }
    def self.fetch_api_files!
      download_queue = if Homebrew::EnvConfig.download_concurrency > 1
        require "download_queue"
        Homebrew::DownloadQueue.new
      end

      stale_seconds = if ENV["HOMEBREW_API_UPDATED"].present? ||
                         (Homebrew::EnvConfig.no_auto_update? && !Homebrew::EnvConfig.force_api_auto_update?)
        nil
      elsif Homebrew.auto_update_command?
        Homebrew::EnvConfig.api_auto_update_secs.to_i
      else
        DEFAULT_API_STALE_SECONDS
      end

      if Homebrew::EnvConfig.use_internal_api?
        Homebrew::API::Internal.fetch_formula_api!(download_queue:, stale_seconds:)
        Homebrew::API::Internal.fetch_cask_api!(download_queue:, stale_seconds:)
      else
        Homebrew::API::Formula.fetch_api!(download_queue:, stale_seconds:)
        Homebrew::API::Formula.fetch_tap_migrations!(download_queue:, stale_seconds: DEFAULT_API_STALE_SECONDS)
        Homebrew::API::Cask.fetch_api!(download_queue:, stale_seconds:)
        Homebrew::API::Cask.fetch_tap_migrations!(download_queue:, stale_seconds: DEFAULT_API_STALE_SECONDS)
      end

      ENV["HOMEBREW_API_UPDATED"] = "1"

      return unless download_queue

      begin
        download_queue.fetch
      ensure
        download_queue.shutdown
      end
    end

    sig { void }
    def self.write_names_and_aliases
      if Homebrew::EnvConfig.use_internal_api?
        Homebrew::API::Internal.write_formula_names_and_aliases
        Homebrew::API::Internal.write_cask_names
      else
        Homebrew::API::Formula.write_names_and_aliases
        Homebrew::API::Cask.write_names
      end
    end

    sig { params(names: T::Array[String], type: String, regenerate: T::Boolean).returns(T::Boolean) }
    def self.write_names_file!(names, type, regenerate:)
      names_path = HOMEBREW_CACHE_API/"#{type}_names.txt"
      if !names_path.exist? || regenerate
        names_path.unlink if names_path.exist?
        names_path.write(names.sort.join("\n"))
        return true
      end

      false
    end

    sig { params(aliases: T::Hash[String, String], type: String, regenerate: T::Boolean).returns(T::Boolean) }
    def self.write_aliases_file!(aliases, type, regenerate:)
      aliases_path = HOMEBREW_CACHE_API/"#{type}_aliases.txt"
      if !aliases_path.exist? || regenerate
        aliases_text = aliases.map do |alias_name, real_name|
          "#{alias_name}|#{real_name}"
        end
        aliases_path.unlink if aliases_path.exist?
        aliases_path.write(aliases_text.sort.join("\n"))
        return true
      end

      false
    end

    sig {
      params(json_data: T::Hash[String, T.untyped])
        .returns([T::Boolean, T.any(String, T::Array[T.untyped], T::Hash[String, T.untyped])])
    }
    private_class_method def self.verify_and_parse_jws(json_data)
      signatures = json_data["signatures"]
      homebrew_signature = signatures&.find { |sig| sig.dig("header", "kid") == "homebrew-1" }
      return false, "key not found" if homebrew_signature.nil?

      header = JSON.parse(Base64.urlsafe_decode64(homebrew_signature["protected"]))
      if header["alg"] != "PS512" || header["b64"] != false # NOTE: nil has a meaning of true
        return false, "invalid algorithm"
      end

      require "openssl"

      pubkey = OpenSSL::PKey::RSA.new((HOMEBREW_LIBRARY_PATH/"api/homebrew-1.pem").read)
      signing_input = "#{homebrew_signature["protected"]}.#{json_data["payload"]}"
      unless pubkey.verify_pss("SHA512",
                               Base64.urlsafe_decode64(homebrew_signature["signature"]),
                               signing_input,
                               salt_length: :digest,
                               mgf1_hash:   "SHA512")
        return false, "signature mismatch"
      end

      [true, JSON.parse(json_data["payload"], freeze: true)]
    end

    sig { params(path: Pathname).returns(T.nilable(Tap)) }
    def self.tap_from_source_download(path)
      path = path.expand_path
      source_relative_path = path.relative_path_from(Homebrew::API::HOMEBREW_CACHE_API_SOURCE)
      return if source_relative_path.to_s.start_with?("../")

      org, repo = source_relative_path.each_filename.first(2)
      return if org.blank? || repo.blank?

      Tap.fetch(org, repo)
    end

    sig { returns(T::Array[String]) }
    def self.formula_names
      if Homebrew::EnvConfig.use_internal_api?
        Homebrew::API::Internal.formula_arrays.keys
      else
        Homebrew::API::Formula.all_formulae.keys
      end
    end

    sig { returns(T::Hash[String, String]) }
    def self.formula_aliases
      if Homebrew::EnvConfig.use_internal_api?
        Homebrew::API::Internal.formula_aliases
      else
        Homebrew::API::Formula.all_aliases
      end
    end

    sig { returns(T::Hash[String, String]) }
    def self.formula_renames
      if Homebrew::EnvConfig.use_internal_api?
        Homebrew::API::Internal.formula_renames
      else
        Homebrew::API::Formula.all_renames
      end
    end

    sig { returns(T::Hash[String, String]) }
    def self.formula_tap_migrations
      if Homebrew::EnvConfig.use_internal_api?
        Homebrew::API::Internal.formula_tap_migrations
      else
        Homebrew::API::Formula.tap_migrations
      end
    end

    sig { returns(Pathname) }
    def self.cached_formula_json_file_path
      if Homebrew::EnvConfig.use_internal_api?
        Homebrew::API::Internal.cached_formula_json_file_path
      else
        Homebrew::API::Formula.cached_json_file_path
      end
    end

    sig { returns(T::Array[String]) }
    def self.cask_tokens
      if Homebrew::EnvConfig.use_internal_api?
        Homebrew::API::Internal.cask_hashes.keys
      else
        Homebrew::API::Cask.all_casks.keys
      end
    end

    sig { returns(T::Hash[String, String]) }
    def self.cask_renames
      if Homebrew::EnvConfig.use_internal_api?
        Homebrew::API::Internal.cask_renames
      else
        Homebrew::API::Cask.all_renames
      end
    end

    sig { returns(T::Hash[String, String]) }
    def self.cask_tap_migrations
      if Homebrew::EnvConfig.use_internal_api?
        Homebrew::API::Internal.cask_tap_migrations
      else
        Homebrew::API::Cask.tap_migrations
      end
    end

    sig { returns(Pathname) }
    def self.cached_cask_json_file_path
      if Homebrew::EnvConfig.use_internal_api?
        Homebrew::API::Internal.cached_cask_json_file_path
      else
        Homebrew::API::Cask.cached_json_file_path
      end
    end
  end

  sig { type_parameters(:U).params(block: T.proc.returns(T.type_parameter(:U))).returns(T.type_parameter(:U)) }
  def self.with_no_api_env(&block)
    return yield if Homebrew::EnvConfig.no_install_from_api?

    with_env(HOMEBREW_NO_INSTALL_FROM_API: "1", HOMEBREW_AUTOMATICALLY_SET_NO_INSTALL_FROM_API: "1", &block)
  end

  sig {
    type_parameters(:U).params(
      condition: T::Boolean,
      block:     T.proc.returns(T.type_parameter(:U)),
    ).returns(T.type_parameter(:U))
  }
  def self.with_no_api_env_if_needed(condition, &block)
    return yield unless condition

    with_no_api_env(&block)
  end
end
