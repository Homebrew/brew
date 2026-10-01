# typed: strict
# frozen_string_literal: true

require "json"
require "time"
require "unpack_strategy"
require "lock_file"
require "system_command"
require "utils/output"
require "utils/path"

# Need to define this before requiring Mechanize to avoid:
#   uninitialized constant Mechanize
# rubocop:disable Lint/EmptyClass
class Mechanize; end
require "vendor/gems/mechanize/lib/mechanize/http/content_disposition_parser"
# rubocop:enable Lint/EmptyClass

require "utils/curl"
require "utils/github"
require "utils/timer"

require "github_packages"
require "download_strategy/abstract_download_strategy"
require "download_strategy/vcs_download_strategy"
require "download_strategy/abstract_file_download_strategy"
require "download_strategy/curl_download_strategy"
require "download_strategy/pypi_download_strategy"
require "download_strategy/homebrew_curl_download_strategy"
require "download_strategy/curl_github_packages_download_strategy"
require "download_strategy/curl_apache_mirror_download_strategy"
require "download_strategy/curl_post_download_strategy"
require "download_strategy/no_unzip_curl_download_strategy"
require "download_strategy/local_bottle_download_strategy"
require "download_strategy/subversion_download_strategy"
require "download_strategy/git_download_strategy"
require "download_strategy/github_git_download_strategy"
require "download_strategy/cvs_download_strategy"
require "download_strategy/mercurial_download_strategy"
require "download_strategy/bazaar_download_strategy"
require "download_strategy/fossil_download_strategy"
require "download_strategy/download_strategy_detector"

AbstractDownloadStrategy::HOMEBREW_CONTROLLED_STRATEGIES = T.let([
  CurlApacheMirrorDownloadStrategy,
  CurlDownloadStrategy,
  CurlGitHubPackagesDownloadStrategy,
  CurlPostDownloadStrategy,
  HomebrewCurlDownloadStrategy,
  NoUnzipCurlDownloadStrategy,
  PyPIDownloadStrategy,
].freeze, T::Array[T::Class[AbstractDownloadStrategy]])
AbstractDownloadStrategy.private_constant :HOMEBREW_CONTROLLED_STRATEGIES
