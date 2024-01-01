# typed: true
# frozen_string_literal: true

require "download_strategy"
require "version"

# @api private
class URL
  attr_reader :specs, :using

  sig { params(url: String, specs: T::Hash[Symbol, T.untyped]).void }
  def initialize(url, specs = {})
    @url = url.freeze
    @specs = specs.dup
    @using = @specs.delete(:using)
    @specs.freeze
  end

  sig { returns(String) }
  def to_s
    @url
  end

  sig { returns(T.class_of(AbstractDownloadStrategy)) }
  def download_strategy
    @download_strategy ||= DownloadStrategyDetector.detect(@url, @using)
  end

  sig { returns(Version) }
  def version
    @version ||= Version.detect(@url, **@specs)
  end
end
