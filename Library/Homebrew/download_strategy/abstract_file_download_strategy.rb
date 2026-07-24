# typed: strict
# frozen_string_literal: true

# @abstract Abstract superclass for all download strategies downloading a single file.
class AbstractFileDownloadStrategy < AbstractDownloadStrategy
  abstract!

  # Path for storing an incomplete download while the download is still in progress.
  #
  # @api public
  sig { returns(Pathname) }
  def temporary_path
    @temporary_path ||= T.let(Pathname.new("#{cached_location}.incomplete"), T.nilable(Pathname))
  end

  # Path of the symlink (whose name includes the resource name, version and extension)
  # pointing to {#cached_location}.
  #
  # @api public
  sig { returns(Pathname) }
  def symlink_location
    return T.must(@symlink_location) if defined?(@symlink_location)

    ext = Pathname(parse_basename(url)).extname
    @symlink_location = T.let(@cache/Utils.safe_filename("#{name}--#{version}#{ext}"), T.nilable(Pathname))
    T.must(@symlink_location)
  end

  # Path for storing the completed download.
  #
  # @api public
  sig { override.returns(Pathname) }
  def cached_location
    return @cached_location if @cached_location

    url_sha256 = Digest::SHA256.hexdigest(url)
    downloads = Pathname.glob(HOMEBREW_CACHE/"downloads/#{url_sha256}--*")
                        .reject { |path| path.extname.end_with?(".incomplete") }

    @cached_location = T.let(
      if downloads.one?
        downloads.fetch(0)
      else
        HOMEBREW_CACHE/"downloads/#{url_sha256}--#{Utils.safe_filename(resolved_basename)}"
      end, T.nilable(Pathname)
    )
    T.must(@cached_location)
  end

  sig { override.returns(T.nilable(Integer)) }
  def fetched_size
    File.size?(temporary_path) || File.size?(cached_location)
  end

  sig { returns(Pathname) }
  def basename
    cached_location.basename.sub(/^[\da-f]{64}--/, "")
  end

  sig { params(target_cached_location: Pathname).void }
  def create_symlink_to_cached_download(target_cached_location)
    symlink_location.dirname.mkpath
    FileUtils.ln_s target_cached_location.relative_path_from(symlink_location.dirname), symlink_location, force: true
  end

  sig { params(url: String, search_query: T::Boolean).returns(String) }
  def parse_basename(url, search_query: true)
    components = { path: T.let([], T::Array[String]), query: T.let([], T::Array[String]) }

    file_url = T.let(false, T::Boolean)
    if url.match?(URI::RFC2396_PARSER.make_regexp)
      uri = URI(url)
      file_url = uri.scheme == "file"

      if (uri_query = uri.query.presence)
        URI.decode_www_form(uri_query).each do |key, param|
          components[:query] << param if search_query

          next if key != "response-content-disposition"

          query_basename = param[/attachment;\s*filename=(["']?)(.+)\1/i, 2]
          return File.basename(query_basename) if query_basename
        end
      end

      if (uri_path = uri.path.presence)
        components[:path] = uri_path.split("/").filter_map do |part|
          URI::RFC2396_PARSER.unescape(part).presence
        end
      end
    else
      components[:path] = [url]
    end

    # We need a Pathname because we've monkeypatched extname to support double
    # extensions (e.g. tar.gz).
    # Given a URL like https://example.com/download.php?file=foo-1.0.tar.gz
    # the basename we want is "foo-1.0.tar.gz", not "download.php".
    # Skipped for file:// URLs since their paths can contain ancestor
    # directories with dots (e.g. "github.com") that aren't real extensions.
    unless file_url
      [*components[:path], *components[:query]].reverse_each do |path|
        path = Pathname(path)
        return path.basename.to_s if path.extname.present?
      end
    end

    filename = components[:path].last
    return "" if filename.blank?

    File.basename(filename)
  end

  private

  sig { returns(String) }
  def resolved_basename
    _, resolved_basename = resolved_url_and_basename
    resolved_basename
  end

  sig { returns([String, String]) }
  def resolved_url_and_basename
    return T.must(@resolved_url_and_basename) if defined?(@resolved_url_and_basename)

    T.must(@resolved_url_and_basename = T.let([url, parse_basename(url)], T.nilable([String, String])))
  end
end
