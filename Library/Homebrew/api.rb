# typed: strict
# frozen_string_literal: true

require "api/analytics"
require "api/env"
require "utils/output"

# Runtime signature checks happen before lazy method-body requires run.
require "download_queue" if ENV["HOMEBREW_SORBET_RUNTIME"]

module Homebrew
  # Helper functions for using Homebrew's formulae.brew.sh API.
  module API
    DownloadQueueType = T.type_alias { T.nilable(Homebrew::DownloadQueue) }

    require "api/cask"
    require "api/formula"
    require "api/internal"
    require "api/formula_struct"
    require "api/cask_struct"
    require "api/packages_index"

    extend Utils::Output::Mixin

    HOMEBREW_CACHE_API = T.let((HOMEBREW_CACHE/"api").freeze, Pathname)
    HOMEBREW_CACHE_API_SOURCE = T.let((HOMEBREW_CACHE/"api-source").freeze, Pathname)
    DEFAULT_API_STALE_SECONDS = T.let(7 * 24 * 60 * 60, Integer) # 7 days
    # Revalidate unsigned per-resource responses hourly to limit how long a
    # poisoned cache can persist without requiring a request for every command.
    UNSIGNED_API_STALE_SECONDS = T.let(60 * 60, Integer)

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
        download_queue: DownloadQueueType,
        enqueue:        T::Boolean,
      ).returns([T.any(T::Array[T.untyped], T::Hash[String, T.untyped]), T::Boolean])
    }
    def self.fetch_json_api_file(endpoint, target: HOMEBREW_CACHE_API/endpoint,
                                 stale_seconds: nil, download_queue: nil,
                                 enqueue: false)
      # Lazy-load dependency.
      require "development_tools"

      retry_count = 0
      url = "#{Homebrew::EnvConfig.api_domain}/#{endpoint}"
      default_url = "#{HOMEBREW_API_DEFAULT_DOMAIN}/#{endpoint}"

      if Homebrew.running_as_root_but_not_owned_by_root? &&
         (!target.exist? || target.empty?)
        odie "Need to download #{url} but cannot as root! Run `brew update` without `sudo` first then try again."
      end

      curl_args = Utils::Curl.curl_args(retries: 0) + [
        "--compressed",
        "--speed-limit", ENV.fetch("HOMEBREW_CURL_SPEED_LIMIT"),
        "--speed-time", ENV.fetch("HOMEBREW_CURL_SPEED_TIME"),
        # This is a Curl format token, not a Ruby one.
        # rubocop:disable Style/FormatStringToken
        "--write-out", "%{stderr}HTTP status: %{http_code}"
        # rubocop:enable Style/FormatStringToken
      ]

      insecure_download = DevelopmentTools.ca_file_substitution_required? ||
                          DevelopmentTools.curl_substitution_required?
      skip_download = skip_download?(target:, stale_seconds:)

      if enqueue
        unless skip_download
          require "download_queue"
          require "api/json_download"
          download_queue ||= Homebrew::DownloadQueue.default
          download = Homebrew::API::JSONDownload.new(endpoint, target:, stale_seconds:)
          download_queue.enqueue(download)
        end
        return [{}, false]
      end

      json_data, from_payload_cache = begin
        download_succeeded = T.let(false, T::Boolean)
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
            download_succeeded = true
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

        # Only refresh the cache mtime after a successful curl revalidation/download.
        # Touching after a failed download would mark a stale cache as fresh and
        # cause `skip_download?` to short-circuit subsequent retries until cleanup.
        if download_succeeded
          mtime = insecure_download ? Time.new(1970, 1, 1) : Time.now
          FileUtils.touch(target, mtime:)
        end

        payload_data = cached_jws_payload(target) if endpoint.end_with?(".jws.json") && !download_succeeded
        if payload_data
          [payload_data, true]
        else
          # Stat before reading: fingerprinting a concurrently-replaced file
          # against these bytes would poison the payload cache.
          source_stat = target.stat
          # Can use `target.read` again when/if https://github.com/sorbet/sorbet/pull/8999 is merged/released.
          [JSON.parse(File.read(target, encoding: Encoding::UTF_8), freeze: true), false]
        end
      rescue JSON::ParserError
        target.unlink
        retry_count += 1
        skip_download = false
        odie "Cannot download non-corrupt #{url}!" if retry_count > Homebrew::EnvConfig.curl_retries.to_i

        retry
      end

      if endpoint.end_with?(".jws.json") && !from_payload_cache
        success, data = verify_and_parse_jws(json_data)
        unless success
          target.unlink
          odie <<~EOS
            Failed to verify integrity (#{data}) of:
              #{url}
            Potential MITM attempt detected. Please run `brew update` and try again.
          EOS
        end
        # Skip on insecure downloads: their pinned 1970 mtime would make the
        # source fingerprint ambiguous (and they always re-download anyway).
        if source_stat && !insecure_download
          write_jws_payload_cache(target, json_data, source_stat:)
          write_jws_payload_index_cache(target, json_data, parsed: data, source_stat:)
        end
        [data, !skip_download]
      else
        [json_data, !skip_download]
      end
    end

    sig {
      params(json:       T::Hash[String, T.untyped],
             bottle_tag: T.nilable(::Utils::Bottles::Tag)).returns(T::Hash[String, T.untyped])
    }
    def self.merge_variations(json, bottle_tag: nil)
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
      stale_seconds = if ENV["HOMEBREW_API_UPDATED"].present? ||
                         (Homebrew::EnvConfig.no_auto_update? && !Homebrew::EnvConfig.force_api_auto_update?)
        nil
      elsif Homebrew.auto_update_command?
        Homebrew::EnvConfig.api_auto_update_secs.to_i
      else
        DEFAULT_API_STALE_SECONDS
      end

      # The internal API is now always used; read this only to surface its deprecation.
      Homebrew::EnvConfig.use_internal_api?
      target = Internal.cached_packages_json_file_path
      if target.exist? && !target.empty? && skip_download?(target:, stale_seconds:)
        ENV["HOMEBREW_API_UPDATED"] = "1"
        return
      end

      require "download_queue"
      download_queue = Homebrew::DownloadQueue.new
      Homebrew::API::Internal.fetch_packages_api!(download_queue:, stale_seconds:, enqueue: true)

      ENV["HOMEBREW_API_UPDATED"] = "1"

      begin
        download_queue.fetch(heading: "Downloading Homebrew API data")
      ensure
        download_queue.shutdown
      end
    end

    sig { void }
    def self.write_names_and_aliases
      Homebrew::API::Internal.write_formula_names_and_aliases
      Homebrew::API::Internal.write_cask_names
    end

    sig { params(type: String, regenerate: T::Boolean, names: T.proc.returns(T::Array[String])).returns(T::Boolean) }
    def self.write_names_file!(type, regenerate:, &names)
      names_path = HOMEBREW_CACHE_API/"#{type}_names.txt"
      if !names_path.exist? || regenerate
        names_path.unlink if names_path.exist?
        names_path.write(yield.sort.join("\n"))
        return true
      end

      false
    end

    sig {
      params(type: String, regenerate: T::Boolean,
             aliases: T.proc.returns(T::Hash[String, String])).returns(T::Boolean)
    }
    def self.write_aliases_file!(type, regenerate:, &aliases)
      aliases_path = HOMEBREW_CACHE_API/"#{type}_aliases.txt"
      if !aliases_path.exist? || regenerate
        aliases_text = yield.map do |alias_name, real_name|
          "#{alias_name}|#{real_name}"
        end
        aliases_path.unlink if aliases_path.exist?
        aliases_path.write(aliases_text.sort.join("\n"))
        return true
      end

      false
    end

    sig {
      params(
        regenerate: T::Boolean,
        source:     Pathname,
        formulae:   T.proc.returns(T::Hash[String, T::Hash[String, T.untyped]]),
      ).returns(T::Boolean)
    }
    def self.write_executables_file!(regenerate:, source:, &formulae)
      executables_path = HOMEBREW_CACHE_API/"internal/executables.txt"
      # The file is derived only from the API data in `source`, so it stays
      # current until that file next changes or is revalidated.
      executables_mtime, source_mtime = [executables_path, source].map do |path|
        path.mtime
      rescue Errno::ENOENT
        nil
      end
      return false if !regenerate && executables_mtime && source_mtime && source_mtime <= executables_mtime

      executables_lines = yield.filter_map do |name, hash|
        executables = T.cast(hash["executables"], T.nilable(T::Array[String]))
        next if executables.blank?

        "#{name}:#{executables.join(" ")}"
      end
      if executables_lines.empty?
        begin
          executables_path.unlink
          return true
        rescue Errno::ENOENT
          return false
        end
      end

      executables_path.dirname.mkpath
      executables_path.write("#{executables_lines.sort.join("\n")}\n")
      true
    end

    sig { params(target: Pathname).returns(T::Boolean) }
    def self.download_executables_file_from_github_packages!(target)
      github_packages_url = "https://ghcr.io/v2/homebrew/command-not-found/executables"
      manifest_args = [
        "--fail", "--location",
        "--header", "Accept: application/vnd.oci.image.manifest.v1+json",
        "#{github_packages_url}/manifests/latest"
      ]
      if HOMEBREW_GITHUB_PACKAGES_AUTH.present?
        manifest_args.insert(-2, "--header", "Authorization: #{HOMEBREW_GITHUB_PACKAGES_AUTH}")
      end

      manifest_output = Utils::Curl.curl_output(*manifest_args, show_error: false)
      return false unless manifest_output.success?

      manifest = JSON.parse(manifest_output.stdout)
      layers = T.cast(manifest.fetch("layers"), T::Array[T::Hash[String, T.untyped]])
      layer = layers.find do |candidate|
        candidate.dig("annotations", "org.opencontainers.image.title") == target.basename.to_s
      end
      return false if layer.nil?

      digest = T.cast(layer["digest"], T.nilable(String))
      return false if digest.blank?

      download_args = ["--fail"]
      if HOMEBREW_GITHUB_PACKAGES_AUTH.present?
        download_args += ["--header", "Authorization: #{HOMEBREW_GITHUB_PACKAGES_AUTH}"]
      end
      download_args << "#{github_packages_url}/blobs/#{digest}"
      target.dirname.mkpath
      Utils::Curl.curl_download(*download_args, to: target, show_error: false)
      FileUtils.touch(target)
      true
    rescue ErrorDuringExecution, JSON::ParserError, KeyError, TypeError
      target.unlink if target.exist? && target.empty?

      false
    end

    sig {
      params(json_data: T::Hash[String, T.untyped])
        .returns([T::Boolean, T.any(String, T::Array[T.untyped], T::Hash[String, T.untyped])])
    }
    private_class_method def self.verify_and_parse_jws(json_data)
      homebrew_signature = homebrew_jws_signature(json_data)
      return false, "key not found" if homebrew_signature.nil?

      payload = json_data["payload"].to_s
      error = verify_jws_signature(homebrew_signature["protected"].to_s, homebrew_signature["signature"].to_s,
                                   payload)
      return false, error if error

      [true, JSON.parse(payload, freeze: true)]
    end

    sig { params(json_data: T::Hash[String, T.untyped]).returns(T.nilable(T::Hash[String, T.untyped])) }
    private_class_method def self.homebrew_jws_signature(json_data)
      signatures = json_data["signatures"]
      signatures&.find { |signature| signature.dig("header", "kid") == "homebrew-1" }
    end

    # Returns a short error description or `nil` if the signature verifies.
    sig { params(protected_b64: String, signature_b64: String, payload: String).returns(T.nilable(String)) }
    private_class_method def self.verify_jws_signature(protected_b64, signature_b64, payload)
      header = JSON.parse(urlsafe_decode64(protected_b64))
      if !header.is_a?(Hash) || header["alg"] != "PS512" || header["b64"] != false # NOTE: nil has a meaning of true
        return "invalid algorithm"
      end

      require "openssl"

      pubkey = OpenSSL::PKey::RSA.new(jws_public_key_pem)
      return "signature mismatch" unless pubkey.verify_pss("SHA512",
                                                           urlsafe_decode64(signature_b64),
                                                           "#{protected_b64}.#{payload}",
                                                           salt_length: :digest,
                                                           mgf1_hash:   "SHA512")

      nil
    end

    sig { returns(String) }
    private_class_method def self.jws_public_key_pem
      (HOMEBREW_LIBRARY_PATH/"api/homebrew-1.pem").read
    end

    sig { params(target: Pathname).returns(Pathname) }
    private_class_method def self.jws_payload_cache_path(target)
      Pathname("#{target}.payload")
    end

    # Payload sidecars are only maintained for the internal packages files:
    # `brew cleanup --scrub` and `update.sh` only prune sidecars matching
    # `internal/packages.*.jws.json*` and the other `.jws.json` endpoints
    # are re-downloaded whenever they are used.
    sig { params(target: Pathname).returns(T::Boolean) }
    private_class_method def self.jws_payload_cacheable?(target)
      target.dirname == HOMEBREW_CACHE_API/"internal" &&
        target.basename.to_s.match?(/\Apackages\..*\.jws\.json\z/)
    end

    # The size and modification time identify which envelope a cached
    # payload was extracted from.
    sig { params(stat: File::Stat).returns(T::Hash[String, Integer]) }
    private_class_method def self.jws_source_fingerprint(stat)
      {
        "source_size"     => stat.size,
        "source_mtime_ns" => (stat.mtime.to_r * 1_000_000_000).to_i,
      }
    end

    # Returns the verified raw payload bytes, and the envelope stat they were
    # validated against, for an internal packages endpoint served entirely
    # from a fresh cached envelope's sidecar. Returns nil when a download,
    # revalidation or envelope parse is needed instead.
    sig {
      params(endpoint: String, stale_seconds: T.nilable(Integer))
        .returns(T.nilable([String, File::Stat]))
    }
    def self.cached_internal_packages_payload(endpoint, stale_seconds:)
      target = HOMEBREW_CACHE_API/endpoint
      return unless jws_payload_cacheable?(target)
      return if !target.exist? || target.empty?
      return unless skip_download?(target:, stale_seconds:)

      source_stat = target.stat
      payload = cached_jws_payload_string(target, source_stat:)
      return if payload.nil?

      [payload, source_stat]
    rescue SystemCallError
      nil
    end

    # Loads the signed payload of a `.jws.json` file from the sidecar cache
    # written after a previous verification, if it still matches the file.
    # The signature is verified on every load; only re-parsing the much
    # larger envelope is skipped.
    sig { params(target: Pathname).returns(T.nilable(T.any(T::Array[T.untyped], T::Hash[String, T.untyped]))) }
    private_class_method def self.cached_jws_payload(target)
      payload = cached_jws_payload_string(target, source_stat: target.stat)
      return if payload.nil?

      JSON.parse(payload, freeze: true)
    rescue SystemCallError, JSON::ParserError
      nil
    end

    sig { params(target: Pathname, source_stat: File::Stat).returns(T.nilable(String)) }
    private_class_method def self.cached_jws_payload_string(target, source_stat:)
      return unless jws_payload_cacheable?(target)

      expected_fingerprint = jws_source_fingerprint(source_stat)

      jws_payload_cache_path(target).open("rb") do |file|
        header_line = file.gets
        next if header_line.nil?

        header = JSON.parse(header_line)
        next unless header.is_a?(Hash)
        # Check the fingerprint before reading the payload so a stale
        # sidecar does not cost a wasted multi-megabyte read.
        next if expected_fingerprint.any? { |key, value| header[key] != value }

        protected_b64 = header["protected"]
        signature_b64 = header["signature"]
        next if !protected_b64.is_a?(String) || !signature_b64.is_a?(String)

        payload = file.read.force_encoding(Encoding::UTF_8)
        next unless verify_jws_signature(protected_b64, signature_b64, payload).nil?

        payload
      end
    rescue SystemCallError, ArgumentError, JSON::ParserError
      nil
    end

    # Writes the packages byte-offset index beside the payload sidecar so
    # later loads can parse only the entries they need.
    sig {
      params(target: Pathname, json_data: T.any(T::Array[T.untyped], T::Hash[String, T.untyped]),
             parsed: T.any(String, T::Array[T.untyped], T::Hash[String, T.untyped]),
             source_stat: File::Stat).void
    }
    private_class_method def self.write_jws_payload_index_cache(target, json_data, parsed:, source_stat:)
      return unless jws_payload_cacheable?(target)
      return unless json_data.is_a?(Hash)

      payload = json_data["payload"]
      return if !payload.is_a?(String) || !parsed.is_a?(Hash)

      PackagesIndex.write!(target, payload:, parsed:, source_stat:)
    end

    sig {
      params(target: Pathname, json_data: T.any(T::Array[T.untyped], T::Hash[String, T.untyped]),
             source_stat: File::Stat).void
    }
    private_class_method def self.write_jws_payload_cache(target, json_data, source_stat:)
      return unless jws_payload_cacheable?(target)
      # Never write to a user-owned cache as root, matching `skip_download?`.
      return if Homebrew.running_as_root_but_not_owned_by_root?
      return unless json_data.is_a?(Hash)

      homebrew_signature = homebrew_jws_signature(json_data)
      return if homebrew_signature.nil?

      payload = json_data["payload"]
      protected_b64 = homebrew_signature["protected"]
      signature_b64 = homebrew_signature["signature"]
      return if !payload.is_a?(String) || !protected_b64.is_a?(String) || !signature_b64.is_a?(String)

      header = JSON.generate({
        "protected" => protected_b64,
        "signature" => signature_b64,
        **jws_source_fingerprint(source_stat),
      })
      payload_cache_path = jws_payload_cache_path(target)
      temporary_path = Pathname("#{payload_cache_path}.tmp")
      begin
        temporary_path.open("wb") do |file|
          file.write(header, "\n", payload)
        end
        File.rename(temporary_path, payload_cache_path)
      ensure
        temporary_path.unlink if temporary_path.exist?
      end
    rescue SystemCallError
      nil
    end

    sig { params(value: String).returns(String) }
    private_class_method def self.urlsafe_decode64(value)
      value.tr("-_", "+/").ljust((value.length + 3) & ~3, "=").unpack1("m0")
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
      Homebrew::API::Internal.formula_names
    end

    sig { params(name: String).returns(T::Boolean) }
    def self.formula_name?(name)
      Homebrew::API::Internal.formula_name?(name)
    end

    sig { returns(T::Hash[String, String]) }
    def self.formula_aliases
      Homebrew::API::Internal.formula_aliases
    end

    sig { returns(T::Hash[String, String]) }
    def self.formula_renames
      Homebrew::API::Internal.formula_renames
    end

    sig { returns(T::Hash[String, String]) }
    def self.formula_tap_migrations
      Homebrew::API::Internal.formula_tap_migrations
    end

    sig { returns(T::Array[String]) }
    def self.cask_tokens
      Homebrew::API::Internal.cask_names
    end

    sig { params(token: String).returns(T::Boolean) }
    def self.cask_token?(token)
      Homebrew::API::Internal.cask_name?(token)
    end

    sig { returns(T::Hash[String, String]) }
    def self.cask_renames
      Homebrew::API::Internal.cask_renames
    end

    sig { returns(T::Hash[String, String]) }
    def self.cask_tap_migrations
      Homebrew::API::Internal.cask_tap_migrations
    end

    sig { returns(Pathname) }
    def self.cached_cask_json_file_path
      Homebrew::API::Internal.cached_packages_json_file_path
    end
  end
end
