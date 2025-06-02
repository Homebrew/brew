# frozen_string_literal: true

require_relative "shared_helpers"

if Bundler::SharedHelpers.in_bundle?
  require_relative "../bundler"

  # autoswitch to locked Bundler version if available
  Bundler.auto_switch

  # try to auto_install first before we get to the `Bundler.ui.silence`, so user knows what is happening
  Bundler.auto_install

  if STDOUT.tty? || ENV["BUNDLER_FORCE_TTY"]
    begin
      Bundler.ui.silence { Bundler.setup }
    rescue Bundler::BundlerError => e
      Bundler.ui.error e.message
      Bundler.ui.warn e.backtrace.join("\n") if ENV["DEBUG"]
      if e.is_a?(Bundler::GemNotFound)
        default_bundle = Gem.bin_path("bundler", "bundle")
        current_bundle = Bundler::SharedHelpers.bundle_bin_path
        suggested_bundle = default_bundle == current_bundle ? "bundle" : current_bundle
        suggested_cmd = "#{suggested_bundle} install"
        original_gemfile = Bundler.original_env["BUNDLE_GEMFILE"]
        suggested_cmd += " --gemfile #{original_gemfile}" if original_gemfile
        Bundler.ui.warn "Run `#{suggested_cmd}` to install missing gems."
      end
      exit e.status_code
    end
  else
    Bundler.ui.silence { Bundler.setup }
  end

  # We might be in the middle of shelling out to rubygems
  # (RUBYOPT=-rbundler/setup), so we need to give rubygems the opportunity of
  # not being silent.
  Gem::DefaultUserInteraction.ui = nil
end
