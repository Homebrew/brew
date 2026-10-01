# typed: strict
# frozen_string_literal: true

require "version"

class URL
  sig { returns(T::Hash[Symbol, T.untyped]) }
  attr_reader :specs

  sig { returns(T.nilable(T.any(Symbol, T::Class[AbstractDownloadStrategy]))) }
  attr_reader :using

  sig { params(url: String, specs: T::Hash[Symbol, T.untyped]).void }
  def initialize(url, specs = {})
    @url = T.let(url.freeze, String)
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
    @version ||= T.let(Version.detect(@url, **@specs), T.nilable(Version))
  end
end
