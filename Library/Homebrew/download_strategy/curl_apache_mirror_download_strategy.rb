# typed: strict
# frozen_string_literal: true

# Strategy for downloading a file from an Apache Mirror URL.
#
# @api public
class CurlApacheMirrorDownloadStrategy < CurlDownloadStrategy
  sig { returns(T::Array[String]) }
  def mirrors
    combined_mirrors
  end

  private

  sig { returns(T::Array[String]) }
  def combined_mirrors
    return @combined_mirrors if @combined_mirrors

    backup_mirrors = unless apache_mirrors["in_attic"]
      apache_mirrors.fetch("backup", [])
                    .map { |mirror| "#{mirror}#{apache_mirrors["path_info"]}" }
    end

    all_mirrors = [*@mirrors, *backup_mirrors]
    @combined_mirrors = T.let(all_mirrors, T.nilable(T::Array[String]))
    all_mirrors
  end

  sig { override.params(url: String, timeout: T.nilable(T.any(Float, Integer))).returns(URLMetadata) }
  def resolve_url_basename_time_file_size(url, timeout: nil)
    if url == self.url
      end_time = Time.now + timeout if timeout
      mirror_info = apache_mirrors(timeout:)
      preferred = if mirror_info["in_attic"]
        "https://archive.apache.org/dist/"
      else
        mirror_info["preferred"]
      end
      super("#{preferred}#{mirror_info["path_info"]}", timeout: Utils::Timer.remaining!(end_time))
    else
      super
    end
  end

  sig { params(timeout: T.nilable(T.any(Float, Integer))).returns(T::Hash[String, T.untyped]) }
  def apache_mirrors(timeout: nil)
    return @apache_mirrors if @apache_mirrors

    json = curl_output(
      "--silent", "--location", "#{url}&asjson=1", timeout: timeout || Utils::Timer.remaining!(@fetch_end_time)
    ).stdout
    mirrors = JSON.parse(json)
    @apache_mirrors = T.let(mirrors, T.nilable(T::Hash[String, T.untyped]))
    mirrors
  rescue JSON::ParserError
    raise CurlDownloadStrategyError.new(url, "Couldn't determine mirror, try again later.")
  end
end
