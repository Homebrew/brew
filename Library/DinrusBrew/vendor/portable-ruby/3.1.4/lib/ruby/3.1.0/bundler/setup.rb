# frozen_string_literal: true

require_relative "shared_helpers"

if Bundler::SharedHelpers.in_bundle?
  require_relative "../bundler"

  if STDOUT.tty? || ENV["BUNDLER_FORCE_TTY"]
    begin
      Bundler.ui.silence { Bundler.setup }
    rescue Bundler::BundlerError => e
      Bundler.ui.error e.message
      Bundler.ui.warn e.backtrace.join("\n") if ENV["DEBUG"]
      if e.is_a?(Bundler::GemNotFound)
        Bundler.ui.warn "Run `bundle install` to install missing gems."
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
