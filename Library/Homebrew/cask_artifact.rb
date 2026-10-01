# typed: strict
# frozen_string_literal: true

raise "#{__FILE__} must not be loaded via `require`." if $PROGRAM_NAME != __FILE__

old_trap = trap("INT") { exit! 130 }

require_relative "global"

require "digest"
require "json"
require "cask/config"
require "extend/ENV"
require "install_steps"
require "utils/fork"
require "utils/shell_completion"

module Cask
  # Minimal cask state needed to resolve structured install-step paths and tokens.
  class InstallStepsContext
    sig { returns(T.any(String, T::Array[String])) }
    attr_reader :name

    sig { returns(String) }
    attr_reader :token

    sig { returns(T.nilable(String)) }
    attr_reader :arch

    sig { returns(String) }
    attr_reader :version

    sig { returns(Pathname) }
    attr_reader :staged_path

    sig { returns(Pathname) }
    attr_reader :caskroom_path

    sig { returns(Pathname) }
    attr_reader :home

    sig { returns(Config) }
    attr_reader :config

    sig { params(context: T::Hash[String, T.untyped]).void }
    def initialize(context)
      @name = T.let(context.fetch("name"), T.any(String, T::Array[String]))
      @token = T.let(context.fetch("token"), String)
      @arch = T.let(context["arch"], T.nilable(String))
      @version = T.let(context.fetch("version"), String)
      @staged_path = T.let(Pathname(context.fetch("staged_path")), Pathname)
      @caskroom_path = T.let(Pathname(context.fetch("caskroom_path")), Pathname)
      @home = T.let(Pathname(context.fetch("home")), Pathname)
      @config = T.let(Config.from_json(context.fetch("config"), ignore_invalid_keys: true), Config)
    end

    sig { returns(String) }
    def to_s = token
  end
end

begin
  error_pipe = if ENV.delete("HOMEBREW_CHILD_MESSAGE_CHANNEL")
    Utils.forked_child_channel
  else
    Utils.forked_child_error_pipe
  end

  trap("INT", old_trap)

  # Match formula post-install isolation inside the sandboxed child. The
  # original cask context is supplied in JSON and never needs a `.rb` file.
  ENV["TMPDIR"] = HOMEBREW_TEMP.to_s
  ENV["TEMP"] = HOMEBREW_TEMP.to_s
  ENV["TMP"] = HOMEBREW_TEMP.to_s
  ENV.delete("HOMEBREW_PATH")
  ENV["PATH"] = PATH.new(ORIGINAL_PATHS).to_s
  ENV.clear_sensitive_environment!
  ENV.activate_extensions!
  Pathname.activate_extensions!

  payload_json = File.binread(ARGV.fetch(0))
  if Digest::SHA256.hexdigest(payload_json) != ARGV.fetch(1)
    raise "Cask sandbox payload checksum mismatch."
  end

  payload = T.cast(JSON.parse(payload_json), T::Hash[String, T.untyped])
  case payload.fetch("action")
  when "install_steps"
    context = Cask::InstallStepsContext.new(payload.fetch("context"))
    steps = payload.fetch("steps")
    phase = payload.fetch("phase").to_sym
    # Privileged steps execute in the parent process to reuse its sudo ticket
    # (see Cask::Artifact::AbstractInstallSteps#run_steps). Request each step
    # by index and wait for the outcome so ordering is preserved.
    privileged_step_handler = if error_pipe.is_a?(Utils::ForkedChildChannel)
      proc do |index|
        error_pipe.puts JSON.generate(
          "type"  => Homebrew::InstallSteps::Runner::PRIVILEGED_STEP_REQUEST,
          "index" => index,
        )
        error_pipe.flush
        response = error_pipe.gets&.chomp
        next if response == Homebrew::InstallSteps::Runner::PRIVILEGED_STEP_SUCCEEDED

        raise "The parent process failed to run privileged cask install step #{index}."
      end
    else
      proc do |index|
        raise "Privileged cask install step #{index} requires a parent message channel."
      end
    end
    Homebrew::InstallSteps::Runner.new(context:).run(steps, phase:, privileged_step_handler:)
  when "generated_completions"
    errors = []
    payload.fetch("completions").each do |completion|
      commands = completion.fetch("commands")
      output_path = Pathname(completion.fetch("output_path"))
      output_path.dirname.mkpath
      output_path.write(
        Utils::ShellCompletion.generate_completion_output(
          commands,
          completion["shell_parameter"],
          completion.fetch("env"),
          print_stderr: completion.fetch("print_stderr"),
        ),
      )
    rescue => e
      errors << "Failed to generate #{completion.fetch("shell")} completions from #{commands.fetch(0)}: #{e}"
    end
    raise errors.join("\n") unless errors.empty?
  else
    raise ArgumentError, "unknown sandboxed cask action: #{payload.fetch("action")}"
  end

# Handle all possible exceptions.
rescue Exception => e # rubocop:disable Lint/RescueException
  Utils.report_forked_child_error(error_pipe, e)
  exit! 1
end
