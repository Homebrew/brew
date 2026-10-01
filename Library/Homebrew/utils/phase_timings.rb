# typed: strict
# frozen_string_literal: true

module Homebrew
  module PhaseTimings
    Event = T.type_alias { T::Hash[String, T.any(Integer, String)] }

    @command = T.let([], T::Array[String])
    @events = T.let([], T::Array[Event])
    @mutex = T.let(Thread::Mutex.new, Thread::Mutex)
    @output_path = T.let(nil, T.nilable(Pathname))
    @started_at = T.let(0.0, Float)

    sig {
      params(
        output_path: T.any(Pathname, String),
        started_at:  Float,
        command:     T::Array[String],
      ).void
    }
    def self.start!(output_path:, started_at:, command:)
      @output_path = Pathname(output_path)
      @started_at = started_at
      @command = command
      @mutex.synchronize { @events = [] }
      record("startup", started_at, monotonic_time)
    end

    sig {
      type_parameters(:U)
        .params(
          phase:  String,
          detail: T.nilable(String),
          _block: T.proc.returns(T.type_parameter(:U)),
        )
        .returns(T.type_parameter(:U))
    }
    def self.measure(phase, detail: nil, &_block)
      # Recording is opt-in via `$HOMEBREW_PHASE_TIMINGS`, so callers on the
      # startup path can measure unconditionally without paying for it.
      return yield if @output_path.nil?

      started_at = monotonic_time
      begin
        yield
      ensure
        record(phase, started_at, monotonic_time, detail:)
      end
    end

    sig { void }
    def self.install!
      # A class can only be instrumented once it is loaded, so load the install
      # path here rather than reporting zero for phases a command loads later.
      measure("instrumentation") do
        require "cleanup"
        require "download_queue"
        require "formula_installer"
      end

      instrument(Homebrew::CLI::NamedArgs, :to_formulae_and_casks, "formula_resolution") if defined?(Homebrew::CLI)
      instrument(Formulary.singleton_class, :factory, "formula_inflation") if defined?(Formulary)
      instrument(Homebrew::API.singleton_class, :fetch_api_files!, "api_metadata_load") if defined?(Homebrew::API)
      if defined?(Homebrew::API::Internal)
        instrument(Homebrew::API::Internal.singleton_class, :formula_struct, "api_metadata_load")
      end
      if defined?(Homebrew::Install)
        instrument(Homebrew::Install.singleton_class, :formula_installers, "planning")
        instrument(Homebrew::Install.singleton_class, :perform_preinstall_checks_once, "preinstall_checks")
      end
      instrument(FormulaInstaller, :prelude, "planning")
      instrument(FormulaInstaller, :compute_dependencies, "dependency_resolution")
      instrument(FormulaInstaller, :pour, "pour")
      instrument(FormulaInstaller, :link, "link")
      instrument(FormulaInstaller, :clean, "cleanup")
      instrument(FormulaInstaller, :post_install, "postinstall")
      instrument(Homebrew::DownloadQueue, :enqueue, "download_enqueue")
      instrument(Cleanup.singleton_class, :install_formula_clean!, "cleanup")
      if defined?(Utils::Curl)
        instrument(Utils::Curl, :curl_headers, "curl_headers")
        instrument(Utils::Curl.singleton_class, :curl_headers, "curl_headers")
        instrument(Utils::Curl, :curl_download, "curl_body")
        instrument(Utils::Curl.singleton_class, :curl_download, "curl_body")
      end
      instrument(Downloadable::VerificationCache, :verify, "checksum") if defined?(Downloadable::VerificationCache)
      if defined?(AbstractFileDownloadStrategy)
        instrument(AbstractFileDownloadStrategy, :create_symlink_to_cached_download, "symlink")
      end
      instrument(AbstractDownloadStrategy, :stage, "extraction") if defined?(AbstractDownloadStrategy)
      instrument(Bottle, :stage_from_download_queue, "extraction") if defined?(Bottle)
      instrument(Cask::Download, :stage_from_download_queue, "extraction") if defined?(Cask::Download)
      instrument(Tab, :write, "tab_write") if defined?(Tab)
    end

    sig { void }
    def self.write!
      output_path = @output_path
      return if output_path.nil?

      require "json"

      events = @mutex.synchronize { @events.sort_by { |event| event.fetch("start") } }
      output_path.dirname.mkpath
      output_path.write("#{JSON.pretty_generate({
        "schema_version" => 1,
        "time_unit"      => "microseconds",
        "command"        => @command,
        "events"         => events,
      })}\n")
    end

    sig { params(receiver: Object, args: T::Array[T.anything]).returns(T.nilable(String)) }
    def self.detail_for(receiver, args)
      object = if receiver.respond_to?(:formula)
        receiver.public_method(:formula).call
      elsif receiver.respond_to?(:url)
        receiver.public_method(:url).call
      else
        args.first
      end

      if object.respond_to?(:full_name)
        object.full_name.to_s
      elsif object.respond_to?(:download_queue_name)
        object.download_queue_name.to_s
      elsif object.is_a?(String) || object.is_a?(Symbol) || object.is_a?(Pathname)
        object.to_s
      end
    end

    sig { params(klass: T::Module[T.anything], method_name: Symbol, phase: String).void }
    private_class_method def self.instrument(klass, method_name, phase)
      visibility = if klass.private_method_defined?(method_name)
        :private
      elsif klass.protected_method_defined?(method_name)
        :protected
      elsif klass.method_defined?(method_name)
        :public
      end
      return if visibility.nil?

      wrapper = Module.new do
        define_method(method_name) do |*args, **kwargs, &block|
          Homebrew::PhaseTimings.measure(
            phase,
            detail: Homebrew::PhaseTimings.detail_for(self, args),
          ) { super(*args, **kwargs, &block) }
        end
      end
      wrapper.module_eval { private method_name } if visibility == :private
      wrapper.module_eval { protected method_name } if visibility == :protected
      klass.prepend(wrapper)
    end

    sig {
      params(
        phase:        String,
        started_at:   Float,
        completed_at: Float,
        detail:       T.nilable(String),
      ).void
    }
    private_class_method def self.record(phase, started_at, completed_at, detail: nil)
      event = T.let({
        "phase"     => phase,
        "start"     => ((started_at - @started_at) * 1_000_000).round,
        "duration"  => ((completed_at - started_at) * 1_000_000).round,
        "thread_id" => Thread.current.object_id,
      }, Event)
      event["detail"] = detail if detail
      @mutex.synchronize { @events << event }
    end

    sig { returns(Float) }
    private_class_method def self.monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC).to_f
    end
  end
end
