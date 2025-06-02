# frozen_string_literal: true

require_relative "vendored_thor"

module Bundler
  module FriendlyErrors
    module_function

    def enable!
      @disabled = false
    end

    def disabled?
      @disabled
    end

    def disable!
      @disabled = true
    end

    def log_error(error)
      case error
      when YamlSyntaxError
        Bundler.ui.error error.message
        Bundler.ui.trace error.orig_exception
      when Dsl::DSLError, GemspecError
        Bundler.ui.error error.message
      when GemRequireError
        Bundler.ui.error error.message
        Bundler.ui.trace error.orig_exception
      when BundlerError
        if Bundler.ui.debug?
          Bundler.ui.trace error
        else
          Bundler.ui.error error.message, :wrap => true
        end
      when Thor::Error
        Bundler.ui.error error.message
      when LoadError
        raise error unless error.message =~ /cannot load such file -- openssl|openssl.so|libcrypto.so/
        Bundler.ui.error "\nCould not load OpenSSL. #{error.class}: #{error}\n#{error.backtrace.join("\n  ")}"
      when Interrupt
        Bundler.ui.error "\nQuitting..."
        Bundler.ui.trace error
      when Gem::InvalidSpecificationException
        Bundler.ui.error error.message, :wrap => true
      when SystemExit
      when *[defined?(Java::JavaLang::OutOfMemoryError) && Java::JavaLang::OutOfMemoryError].compact
        Bundler.ui.error "\nYour JVM has run out of memory, and Bundler cannot continue. " \
          "You can decrease the amount of memory Bundler needs by removing gems from your Gemfile, " \
          "especially large gems. (Gems can be as large as hundreds of megabytes, and Bundler has to read those files!). " \
          "Alternatively, you can increase the amount of memory the JVM is able to use by running Bundler with jruby -J-Xmx1024m -S bundle (JRuby defaults to 500MB)."
      else request_issue_report_for(error)
      end
    end

    def exit_status(error)
      case error
      when BundlerError then error.status_code
      when Thor::Error then 15
      when SystemExit then error.status
      else 1
      end
    end

    def request_issue_report_for(e)
      Bundler.ui.error <<-EOS.gsub(/^ {8}/, ""), nil, nil
        --- ERROR REPORT TEMPLATE -------------------------------------------------------

        ```
        #{exception_message(e)}
        ```

        #{Bundler::Env.report}
        --- TEMPLATE END ----------------------------------------------------------------

      EOS

      Bundler.ui.error "Unfortunately, an unexpected error occurred, and Bundler cannot continue."

      Bundler.ui.error <<-EOS.gsub(/^ {8}/, ""), nil, :yellow

        First, try this link to see if there are any existing issue reports for this error:
        #{issues_url(e)}

        If there aren't any reports for this error yet, please fill in the new issue form located at #{new_issue_url}, and copy and paste the report template above in there.
      EOS
    end

    def exception_message(error)
      message = serialized_exception_for(error)
      cause = error.cause
      return message unless cause

      message + serialized_exception_for(cause)
    end

    def serialized_exception_for(e)
      <<-EOS.gsub(/^ {8}/, "")
        #{e.class}: #{e.message}
          #{e.backtrace && e.backtrace.join("\n          ").chomp}
      EOS
    end

    def issues_url(exception)
      message = exception.message.lines.first.tr(":", " ").chomp
      message = message.split("-").first if exception.is_a?(Errno)
      require "cgi"
      "https://github.com/rubygems/rubygems/search?q=" \
        "#{CGI.escape(message)}&type=Issues"
    end

    def new_issue_url
      "https://github.com/rubygems/rubygems/issues/new?labels=Bundler&template=bundler-related-issue.md"
    end
  end

  def self.with_friendly_errors
    FriendlyErrors.enable!
    yield
  rescue SignalException
    raise
  rescue Exception => e # rubocop:disable Lint/RescueException
    raise if FriendlyErrors.disabled?

    FriendlyErrors.log_error(e)
    exit FriendlyErrors.exit_status(e)
  end
end
