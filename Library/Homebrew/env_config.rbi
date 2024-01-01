# typed: strict

module Homebrew::EnvConfig
  sig { returns(T.nilable(String)) }
  def self.all_proxy; end

  sig { returns(Integer) }
  def self.api_auto_update_secs; end

  sig { returns(String) }
  def self.api_domain; end

  sig { returns(String) }
  def self.arch; end

  sig { returns(T.nilable(String)) }
  def self.artifact_domain; end

  sig { returns(T.nilable(String)) }
  def self.auto_update_secs; end

  sig { returns(T::Boolean) }
  def self.autoremove?; end

  sig { returns(T::Boolean) }
  def self.bat?; end

  sig { returns(T.nilable(String)) }
  def self.bat_config_path; end

  sig { returns(T.nilable(String)) }
  def self.bat_theme; end

  sig { returns(T::Boolean) }
  def self.bootsnap?; end

  sig { returns(String) }
  def self.bottle_domain; end

  sig { returns(String) }
  def self.brew_git_remote; end

  sig { returns(T.nilable(String)) }
  def self.browser; end

  sig { returns(String) }
  def self.cache; end

  sig { returns(Integer) }
  def self.cleanup_max_age_days; end

  sig { returns(Integer) }
  def self.cleanup_periodic_full_days; end

  sig { returns(T::Boolean) }
  def self.color?; end

  sig { returns(String) }
  def self.core_git_remote; end

  sig { returns(String) }
  def self.curl_path; end

  sig { returns(Integer) }
  def self.curl_retries; end

  sig { returns(T::Boolean) }
  def self.curl_verbose?; end

  sig { returns(T.nilable(String)) }
  def self.curlrc; end

  sig { returns(T::Boolean) }
  def self.debug?; end

  sig { returns(T::Boolean) }
  def self.developer?; end

  sig { returns(T::Boolean) }
  def self.disable_load_formula?; end

  sig { returns(T.nilable(String)) }
  def self.display; end

  sig { returns(T::Boolean) }
  def self.display_install_times?; end

  sig { returns(T.nilable(String)) }
  def self.docker_registry_basic_auth_token; end

  sig { returns(T.nilable(String)) }
  def self.docker_registry_token; end

  sig { returns(T.nilable(String)) }
  def self.editor; end

  sig { returns(T::Boolean) }
  def self.eval_all?; end

  sig { returns(Integer) }
  def self.fail_log_lines; end

  sig { returns(T.nilable(String)) }
  def self.forbidden_licenses; end

  sig { returns(T::Boolean) }
  def self.force_brewed_ca_certificates?; end

  sig { returns(T::Boolean) }
  def self.force_brewed_curl?; end

  sig { returns(T::Boolean) }
  def self.force_brewed_git?; end

  sig { returns(T::Boolean) }
  def self.force_vendor_ruby?; end

  sig { returns(T.nilable(String)) }
  def self.ftp_proxy; end

  sig { returns(T.nilable(String)) }
  def self.git_email; end

  sig { returns(T.nilable(String)) }
  def self.git_name; end

  sig { returns(String) }
  def self.git_path; end

  sig { returns(T.nilable(String)) }
  def self.github_api_token; end

  sig { returns(T.nilable(String)) }
  def self.github_packages_token; end

  sig { returns(T.nilable(String)) }
  def self.github_packages_user; end

  sig { returns(T.nilable(String)) }
  def self.http_proxy; end

  sig { returns(T.nilable(String)) }
  def self.https_proxy; end

  sig { returns(String) }
  def self.install_badge; end

  sig { returns(String) }
  def self.livecheck_watchlist; end

  sig { returns(String) }
  def self.logs; end

  sig { returns(T::Boolean) }
  def self.no_analytics?; end

  sig { returns(T::Boolean) }
  def self.no_auto_update?; end

  sig { returns(T::Boolean) }
  def self.no_bootsnap?; end

  sig { returns(T.nilable(String)) }
  def self.no_cleanup_formulae; end

  sig { returns(T::Boolean) }
  def self.no_color?; end

  sig { returns(T::Boolean) }
  def self.no_emoji?; end

  sig { returns(T::Boolean) }
  def self.no_env_hints?; end

  sig { returns(T::Boolean) }
  def self.no_github_api?; end

  sig { returns(T::Boolean) }
  def self.no_insecure_redirect?; end

  sig { returns(T::Boolean) }
  def self.no_install_cleanup?; end

  sig { returns(T::Boolean) }
  def self.no_install_from_api?; end

  sig { returns(T::Boolean) }
  def self.no_install_upgrade?; end

  sig { returns(T::Boolean) }
  def self.no_installed_dependents_check?; end

  sig { returns(T.nilable(String)) }
  def self.no_proxy; end

  sig { returns(T::Boolean) }
  def self.no_update_report_new?; end

  sig { returns(T.nilable(String)) }
  def self.pip_index_url; end

  sig { returns(T::Boolean) }
  def self.pry?; end

  sig { returns(T::Boolean) }
  def self.simulate_macos_on_linux?; end

  sig { returns(T::Boolean) }
  def self.skip_or_later_bottles?; end

  sig { returns(T::Boolean) }
  def self.sorbet_runtime?; end

  sig { returns(T.nilable(String)) }
  def self.ssh_config_path; end

  sig { returns(T.nilable(String)) }
  def self.sudo_askpass; end

  sig { returns(T::Boolean) }
  def self.sudo_through_sudo_user?; end

  sig { returns(T.nilable(String)) }
  def self.svn; end

  sig { returns(T::Boolean) }
  def self.system_env_takes_priority?; end

  sig { returns(String) }
  def self.temp; end

  sig { returns(T::Boolean) }
  def self.update_to_tag?; end

  sig { returns(T::Boolean) }
  def self.upgrade_greedy?; end

  sig { returns(T::Boolean) }
  def self.verbose?; end

  sig { returns(T::Boolean) }
  def self.verbose_using_dots?; end
end
