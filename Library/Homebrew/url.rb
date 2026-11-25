# typed: strict
# frozen_string_literal: true

require "version"

class URL
  sig { returns(T::Hash[Symbol, T.untyped]) }
  attr_reader :specs

  sig { returns(T.nilable(T.any(Symbol, T::Class[AbstractDownloadStrategy]))) }
  attr_reader :using

  # The mirror used by formula bumps for recognised upstream download URLs.
  sig { params(url: String).returns(T.nilable(String)) }
  def self.automatic_mirror(url)
    scheme, path = url.split("://", 2)
    return if path.nil? || %w[http https ftp].exclude?(scheme&.downcase)

    {
      "ftp.gnu.org/gnu/"                    => "ftpmirror.gnu.org/",
      "download.savannah.gnu.org/"          => "download-mirror.savannah.gnu.org/",
      "www.apache.org/dyn/closer.lua?path=" => "archive.apache.org/dist/",
      "mirrors.ocf.berkeley.edu/debian/"    => "mirrorservice.org/sites/ftp.debian.org/debian/",
    }.each do |upstream, mirror|
      return "#{scheme}://#{mirror}#{path.delete_prefix(upstream)}" if path.start_with?(upstream)
    end
    nil
  end

  sig { params(url: String, specs: T::Hash[Symbol, T.untyped]).void }
  def initialize(url, specs = {})
    @url = T.let(url.freeze, String)
    @version = T.let(nil, T.nilable(Version))
    @specs = T.let(specs.dup, T::Hash[Symbol, T.untyped])
    @using = T.let(@specs.delete(:using), T.nilable(T.any(Symbol, T::Class[AbstractDownloadStrategy])))
    @specs.freeze
  end

  sig { returns(String) }
  def to_s
    @url
  end

  sig { returns(T::Class[AbstractDownloadStrategy]) }
  def download_strategy
    @download_strategy ||=
      T.let(DownloadStrategyDetector.detect(@url, @using), T.nilable(T::Class[AbstractDownloadStrategy]))
  end

  sig { returns(Version) }
  def version
    @version ||= Version.detect(@url, tag: @specs[:tag])
  end
end
