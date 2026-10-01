# typed: strict
# frozen_string_literal: true

require "utils/output"

# Helper class for detecting a download strategy from a URL.
class DownloadStrategyDetector
  sig {
    params(url: String, using: T.nilable(T.any(Symbol, T::Class[AbstractDownloadStrategy])))
      .returns(T::Class[AbstractDownloadStrategy])
  }
  def self.detect(url, using = nil)
    strategy = if using.nil?
      detect_from_url(url)
    elsif using.is_a?(Class) && using < AbstractDownloadStrategy
      using
    elsif using.is_a?(Symbol)
      detect_from_symbol(using)
    else
      raise TypeError,
            "Unknown download strategy specification: #{using.inspect}"
    end

    if strategy == BazaarDownloadStrategy
      Utils::Output.odeprecated "BazaarDownloadStrategy", "GitDownloadStrategy or CurlDownloadStrategy"
    end

    strategy
  end

  sig { params(url: String).returns(T::Class[AbstractDownloadStrategy]) }
  def self.detect_from_url(url)
    case url
    when GitHubPackages::URL_REGEX
      CurlGitHubPackagesDownloadStrategy
    when %r{^https?://github\.com/[^/]+/[^/]+\.git$}
      GitHubGitDownloadStrategy
    when %r{^https?://.+\.git$},
         %r{^git://},
         %r{^https?://git\.sr\.ht/[^/]+/[^/]+$},
         %r{^https?://tangled\.sh/[^/]+/[^/]+$},
         %r{^ssh://git}
      GitDownloadStrategy
    when %r{^https?://www\.apache\.org/dyn/closer\.cgi},
         %r{^https?://www\.apache\.org/dyn/closer\.lua}
      CurlApacheMirrorDownloadStrategy
    when %r{^https?://files\.pythonhosted\.org/packages/}
      PyPIDownloadStrategy
    when %r{^https?://(?:[A-Za-z0-9\-.]+\.)?googlecode\.com/svn},
         %r{^https?://svn\.},
         %r{^svn://},
         %r{^svn\+http://},
         %r{^http://svn\.apache\.org/repos/},
         %r{^https?://(?:[A-Za-z0-9\-.]+\.)?sourceforge\.net/svnroot/}
      SubversionDownloadStrategy
    when %r{^cvs://}
      CVSDownloadStrategy
    when %r{^hg://},
         %r{^https?://(?:[A-Za-z0-9\-.]+\.)?googlecode\.com/hg},
         %r{^https?://(?:[A-Za-z0-9\-.]+\.)?sourceforge\.net/hgweb/}
      MercurialDownloadStrategy
    when %r{^bzr://}
      BazaarDownloadStrategy
    when %r{^fossil://}
      FossilDownloadStrategy
    else
      CurlDownloadStrategy
    end
  end

  sig { params(symbol: Symbol).returns(T::Class[AbstractDownloadStrategy]) }
  def self.detect_from_symbol(symbol)
    case symbol
    when :hg                     then MercurialDownloadStrategy
    when :nounzip                then NoUnzipCurlDownloadStrategy
    when :git                    then GitDownloadStrategy
    when :bzr                    then BazaarDownloadStrategy
    when :svn                    then SubversionDownloadStrategy
    when :curl                   then CurlDownloadStrategy
    when :homebrew_curl          then HomebrewCurlDownloadStrategy
    when :cvs                    then CVSDownloadStrategy
    when :post                   then CurlPostDownloadStrategy
    when :fossil                 then FossilDownloadStrategy
    else
      raise TypeError, "Unknown download strategy #{symbol} was requested."
    end
  end
end
