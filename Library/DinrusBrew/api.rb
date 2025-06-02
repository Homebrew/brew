# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "api/analytics"
require "api/cask"
require "api/formula"
require "base64" # TODO: vendor this for Ruby 3.4.

module DinrusBrew
  # Helper functions for using DinrusBrew's formulae.brew.sh API.
  module API
    extend Cachable

    DINRUSBREW_CACHE_API = (DINRUSBREW_CACHE/"api").freeze
    DINRUSBREW_CACHE_API_SOURCE = (DINRUSBREW_CACHE/"api-source").freeze

    sig { params(endpoint: String).returns(Hash) }
    def self.fetch(endpoint)
      return cache[endpoint] if cache.present? && cache.key?(endpoint)

      api_url = "#{DinrusBrew::EnvConfig.api_domain}/#{endpoint}"
      output = Utils::Curl.curl_output("--fail", api_url)
      if !output.success? && DinrusBrew::EnvConfig.api_domain != DINRUSBREW_API_DEFAULT_DOMAIN
        # Fall back to the default API domain and try again
        api_url = "#{DINRUSBREW_API_DEFAULT_DOMAIN}/#{endpoint}"
        output = Utils::Curl.curl_output("--fail", api_url)
      end
      raise ArgumentError, "Нет файла по адресу #{Tty.underline}#{api_url}#{Tty.reset}" unless output.success?

      cache[endpoint] = JSON.parse(output.stdout, freeze: true)
    rescue JSON::ParserError
      raise ArgumentError, "Неполноценный файл JSON: #{Tty.underline}#{api_url}#{Tty.reset}"
    end

    sig {
      params(endpoint: String, target: Pathname, stale_seconds: Integer).returns([T.any(Array, Hash), T::Boolean])
    }
    def self.fetch_json_api_file(endpoint, target: DINRUSBREW_CACHE_API/endpoint,
                                 stale_seconds: DinrusBrew::EnvConfig.api_auto_update_secs.to_i)
      # Lazy-load dependency.
      require "development_tools"

      retry_count = 0
      url = "#{DinrusBrew::EnvConfig.api_domain}/#{endpoint}"
      default_url = "#{DINRUSBREW_API_DEFAULT_DOMAIN}/#{endpoint}"

      if DinrusBrew.running_as_root_but_not_owned_by_root? &&
         (!target.exist? || target.empty?)
        odie "Нужно загрузить #{url}, но надо не как root! Выполните сначала `brew update` без `sudo`, затем попытайтесь ещё раз."
      end

      curl_args = Utils::Curl.curl_args(retries: 0) + %W[
        --compressed
        --speed-limit #{ENV.fetch("DINRUSBREW_CURL_SPEED_LIMIT")}
        --speed-time #{ENV.fetch("DINRUSBREW_CURL_SPEED_TIME")}
      ]

      insecure_download = DevelopmentTools.ca_file_substitution_required? ||
                          DevelopmentTools.curl_substitution_required?
      skip_download = target.exist? &&
                      !target.empty? &&
                      (!DinrusBrew.auto_update_command? ||
                        (DinrusBrew::EnvConfig.no_auto_update? && !DinrusBrew::EnvConfig.force_api_auto_update?) ||
                      ((Time.now - stale_seconds) < target.mtime))
      skip_download ||= DinrusBrew.running_as_root_but_not_owned_by_root?

      json_data = begin
        begin
          args = curl_args.dup
          args.prepend("--time-cond", target.to_s) if target.exist? && !target.empty?
          if insecure_download
            opoo DevelopmentTools.insecure_download_warning(endpoint)
            args.append("--insecure")
          end
          unless skip_download
            ohai "Загружается #{url}" if $stdout.tty? && !Context.current.quiet?
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

          opoo "#{target.basename}: неудачное обновление, откат к кэшированной версии."
        end

        mtime = insecure_download ? Time.new(1970, 1, 1) : Time.now
        FileUtils.touch(target, mtime:) unless skip_download
        JSON.parse(target.read, freeze: true)
      rescue JSON::ParserError
        target.unlink
        retry_count += 1
        skip_download = false
        odie "Не удаётся загрузить неповреждённый #{url}!" if retry_count > DinrusBrew::EnvConfig.curl_retries.to_i

        retry
      end

      if endpoint.end_with?(".jws.json")
        success, data = verify_and_parse_jws(json_data)
        unless success
          target.unlink
          odie <<~EOS
            Не удалось проверить целостность (#{data}):
              #{url}
            Обнаружена потенциальная попытка MITM. Пжлст, выполните `brew update` и попытайтесь ещё раз.
          EOS
        end
        [data, !skip_download]
      else
        [json_data, !skip_download]
      end
    end

    sig { params(json: Hash).returns(Hash) }
    def self.merge_variations(json)
      return json unless json.key?("variations")

      bottle_tag = ::Utils::Bottles::Tag.new(system: DinrusBrew::SimulateSystem.current_os,
                                             arch:   DinrusBrew::SimulateSystem.current_arch)

      if (variation = json.dig("variations", bottle_tag.to_s).presence)
        json = json.merge(variation)
      end

      json.except("variations")
    end

    sig { params(names: T::Array[String], type: String, regenerate: T::Boolean).returns(T::Boolean) }
    def self.write_names_file(names, type, regenerate:)
      names_path = DINRUSBREW_CACHE_API/"#{type}_names.txt"
      if !names_path.exist? || regenerate
        names_path.write(names.join("\n"))
        return true
      end

      false
    end

    sig { params(json_data: Hash).returns([T::Boolean, T.any(String, Array, Hash)]) }
    private_class_method def self.verify_and_parse_jws(json_data)
      signatures = json_data["signatures"]
      homebrew_signature = signatures&.find { |sig| sig.dig("header", "kid") == "homebrew-1" }
      return false, "ключ не найден" if homebrew_signature.nil?

      header = JSON.parse(Base64.urlsafe_decode64(homebrew_signature["protected"]))
      if header["alg"] != "PS512" || header["b64"] != false # NOTE: nil has a meaning of true
        return false, "неполноценный алгоритм"
      end

      require "openssl"

      pubkey = OpenSSL::PKey::RSA.new((DINRUSBREW_LIBRARY_PATH/"api/homebrew-1.pem").read)
      signing_input = "#{homebrew_signature["protected"]}.#{json_data["payload"]}"
      unless pubkey.verify_pss("SHA512",
                               Base64.urlsafe_decode64(homebrew_signature["signature"]),
                               signing_input,
                               salt_length: :digest,
                               mgf1_hash:   "SHA512")
        return false, "несовпадение сигнатур"
      end

      [true, JSON.parse(json_data["payload"], freeze: true)]
    end

    sig { params(path: Pathname).returns(T.nilable(Tap)) }
    def self.tap_from_source_download(path)
      path = path.expand_path
      source_relative_path = path.relative_path_from(DinrusBrew::API::DINRUSBREW_CACHE_API_SOURCE)
      return if source_relative_path.to_s.start_with?("../")

      org, repo = source_relative_path.each_filename.first(2)
      return if org.blank? || repo.blank?

      Tap.fetch(org, repo)
    end

    sig { returns(T::Boolean) }
    def self.internal_json_v3?
      ENV["DINRUSBREW_INTERNAL_JSON_V3"].present?
    end
  end

  sig { params(block: T.proc.returns(T.untyped)).returns(T.untyped) }
  def self.with_no_api_env(&block)
    return yield if DinrusBrew::EnvConfig.no_install_from_api?

    with_env(DINRUSBREW_NO_INSTALL_FROM_API: "1", DINRUSBREW_AUTOMATICALLY_SET_NO_INSTALL_FROM_API: "1", &block)
  end

  sig { params(condition: T::Boolean, block: T.proc.returns(T.untyped)).returns(T.untyped) }
  def self.with_no_api_env_if_needed(condition, &block)
    return yield unless condition

    with_no_api_env(&block)
  end
end
