# typed: strict
# frozen_string_literal: true

require "formula"
require "cask/cask_loader"
require "tempfile"
require "utils/output"

# Helper module for validating syntax in taps.
module Readall
  extend T::Generic
  extend Cachable
  extend Utils::Output::Mixin

  Cache = type_template { { fixed: T::Hash[Symbol, T.untyped] } }

  private_class_method :cache

  MIN_FILES_PER_WORKER = 4
  private_constant :MIN_FILES_PER_WORKER

  # Buffers Ruby compile warnings from {.syntax_errors_or_warnings?} so they
  # can be filtered before being printed to `$stderr`.
  module WarningBuffer
    sig { params(message: String, category: T.nilable(Symbol)).void }
    def warn(message, category: nil)
      buffer = Readall.warning_buffer
      buffer ? buffer << message : super
    end
  end
  private_constant :WarningBuffer
  Warning.singleton_class.prepend(WarningBuffer)

  @warning_buffer = T.let(nil, T.nilable(T::Array[String]))

  class << self
    sig { returns(T.nilable(T::Array[String])) }
    attr_accessor :warning_buffer
  end

  sig { params(ruby_files: T::Array[Pathname]).returns(T::Boolean) }
  def self.valid_ruby_syntax?(ruby_files)
    parallel_slices_valid?(ruby_files) do |files|
      failed = T.let(false, T::Boolean)
      files.each do |ruby_file|
        # As a side effect, print syntax errors/warnings to `$stderr`.
        failed = true if syntax_errors_or_warnings?(ruby_file)
      end
      !failed
    end
  end

  sig { params(alias_dir: Pathname, formula_dir: Pathname).returns(T::Boolean) }
  def self.valid_aliases?(alias_dir, formula_dir)
    return true unless alias_dir.directory?

    formula_basenames = Set.new(formula_dir.glob("**/*.rb").map { |formula_file| formula_file.basename.to_s })

    failed = T.let(false, T::Boolean)
    alias_dir.each_child do |f|
      if !f.symlink?
        onoe "Non-symlink alias: #{f}"
        failed = true
      elsif !f.file?
        onoe "Non-file alias: #{f}"
        failed = true
      end

      if formula_basenames.include?("#{f.basename}.rb")
        onoe "Formula duplicating alias: #{f}"
        failed = true
      end
    end
    !failed
  end

  sig {
    params(
      tap: Tap, bottle_tag: T.nilable(Utils::Bottles::Tag), files: T.nilable(T::Array[Pathname]),
    ).returns(T::Boolean)
  }
  def self.valid_formulae?(tap, bottle_tag: nil, files: nil)
    cache[:valid_formulae] ||= {}

    success = T.let(true, T::Boolean)
    (files || tap.formula_files).each do |file|
      valid = cache[:valid_formulae][file]
      next if valid == true || valid&.include?(bottle_tag)

      formula_name = file.basename(".rb").to_s
      formula_contents = file.read.force_encoding("UTF-8")

      readall_namespace = "ReadallNamespace"
      readall_formula_class = Formulary.load_formula(formula_name, file, formula_contents, readall_namespace,
                                                     flags: [], ignore_errors: false)
      readall_formula = readall_formula_class.new(formula_name, file, :stable, tap:)
      readall_formula.to_hash
      cache[:valid_formulae][file] = if readall_formula.on_system_blocks_exist?
        [bottle_tag, *cache[:valid_formulae][file]]
      else
        true
      end
    rescue Interrupt
      raise
    # Handle all possible exceptions reading formulae.
    rescue Exception => e # rubocop:disable Lint/RescueException
      onoe "Invalid formula (#{bottle_tag}): #{file}"
      $stderr.puts e
      success = false
    end
    success
  end

  sig {
    params(
      tap: Tap, os_name: T.nilable(Symbol), arch: T.nilable(Symbol), files: T.nilable(T::Array[Pathname]),
    ).returns(T::Boolean)
  }
  def self.valid_casks?(tap, os_name: nil, arch: nil, files: nil)
    validating_linux = if os_name.nil?
      Homebrew::SimulateSystem.current_os == :linux
    else
      os_name == :linux
    end
    return true unless validating_linux

    os_and_arch = "Linux"
    os_and_arch += " on #{(arch == :intel) ? "Intel x86_64" : "ARM64"}" if arch

    success = T.let(true, T::Boolean)
    (files || tap.cask_files).each do |file|
      cask = if arch
        Homebrew::SimulateSystem.with(os: :macos, arch:) do
          loaded_cask = Cask::CaskLoader.load(file)
          loaded_cask if loaded_cask.supports_linux?
        end
      else
        Homebrew::SimulateSystem.with(os: :macos) do
          loaded_cask = Cask::CaskLoader.load(file)
          loaded_cask if loaded_cask.supports_linux?
        end
      end
      next unless cask

      check_linux_sha256 = lambda do
        cask.refresh
        arch_types = cask.depends_on.arch&.map { |cask_arch| cask_arch[:type] }
        # `depends_on arch:` excludes this architecture, so no Linux
        # checksum is expected for it.
        next true if arch_types&.exclude?(Homebrew::SimulateSystem.current_arch)

        !cask.sha256.nil?
      end
      linux_sha256_valid = if arch
        Homebrew::SimulateSystem.with(os: :linux, arch:, &check_linux_sha256)
      else
        Homebrew::SimulateSystem.with(os: :linux, &check_linux_sha256)
      end
      # No `sha256` matched Linux, so the cask cannot be downloaded there
      # despite not being marked macOS-only.
      next if linux_sha256_valid

      onoe "Invalid cask (#{os_and_arch}): #{file}"
      $stderr.puts "Missing Linux stanzas can leave Linux `sha256` as nil. " \
                   "Add `depends_on :macos` if this cask is macOS-only or " \
                   "`depends_on arch:` if it does not support this architecture."
      success = false
    rescue Interrupt
      raise
    # Handle all possible exceptions reading casks.
    rescue Exception => e # rubocop:disable Lint/RescueException
      onoe "Invalid cask (#{os_and_arch}): #{file}"
      $stderr.puts e
      success = false
    end
    success
  end

  sig {
    params(
      tap: Tap, aliases: T::Boolean, no_simulate: T::Boolean, os_arch_combinations: T::Array[[Symbol, Symbol]],
    ).returns(T::Boolean)
  }
  def self.valid_tap?(tap, aliases: false, no_simulate: false,
                      os_arch_combinations: OnSystem::ALL_OS_ARCH_COMBINATIONS)
    success = true

    if aliases
      valid_aliases = valid_aliases?(tap.alias_dir, tap.formula_dir)
      success = false unless valid_aliases
    end

    items = tap.formula_files.map { |file| [:formula, file] } +
            tap.cask_files.map { |file| [:cask, file] }

    all_files_valid = parallel_slices_valid?(items) do |slice|
      formula_files = slice.filter_map { |type, file| file if type == :formula }
      cask_files = slice.filter_map { |type, file| file if type == :cask }

      slice_success = T.let(true, T::Boolean)
      if no_simulate
        slice_success = false unless valid_formulae?(tap, files: formula_files)
        slice_success = false unless valid_casks?(tap, files: cask_files)
      else
        os_arch_combinations.each do |os, arch|
          bottle_tag = Utils::Bottles::Tag.new(system: os, arch:)
          next unless bottle_tag.valid_combination?

          Homebrew::SimulateSystem.with(os:, arch:) do
            slice_success = false unless valid_formulae?(tap, bottle_tag:, files: formula_files)
            slice_success = false unless valid_casks?(tap, os_name: os, arch:, files: cask_files)
          end
        end
      end
      slice_success
    end
    success = false unless all_files_valid

    success
  end

  sig { params(filename: Pathname).returns(T::Boolean) }
  private_class_method def self.syntax_errors_or_warnings?(filename)
    # Compile in-process (much faster than spawning `ruby -c -w` per file),
    # buffering compile warnings so they can be filtered.
    error = T.let(nil, T.nilable(String))
    warnings = self.warning_buffer = []
    old_verbose = $VERBOSE
    $VERBOSE = true
    begin
      RubyVM::InstructionSequence.compile_file(filename.to_s)
    rescue ScriptError, ArgumentError => e
      error = "#{e.message.chomp}\n"
    ensure
      $VERBOSE = old_verbose
      self.warning_buffer = nil
    end

    # Ignore unnecessary warning about named capture conflicts.
    # See https://bugs.ruby-lang.org/issues/12359.
    messages = warnings.grep_v(/named capture conflicts a local variable/).join
    messages += error if error

    $stderr.print messages

    # Both syntax errors and syntax warnings count as failures.
    !messages.chomp.empty?
  end

  sig {
    type_parameters(:U).params(
      items:  T::Array[T.type_parameter(:U)],
      _block: T.proc.params(arg0: T::Array[T.type_parameter(:U)]).returns(T::Boolean),
    ).returns(T::Boolean)
  }
  private_class_method def self.parallel_slices_valid?(items, &_block)
    require "hardware"

    worker_count = [Hardware::CPU.cores, items.length / MIN_FILES_PER_WORKER].min
    return yield(items) if worker_count <= 1

    workers = items.each_slice((items.length.to_f / worker_count).ceil).map do |slice|
      reader, writer = IO.pipe
      stdout_file = Tempfile.new("readall-stdout")
      stderr_file = Tempfile.new("readall-stderr")
      pid = Process.fork do
        reader.close
        success = begin
          # Capture output so parallel workers cannot interleave lines.
          $stdout = stdout_file.to_io
          $stderr = stderr_file.to_io
          yield(slice)
        rescue Interrupt
          false
        # Report any worker exception as a validation failure.
        rescue Exception => e # rubocop:disable Lint/RescueException
          $stderr.puts e.full_message
          false
        ensure
          $stdout.flush
          $stderr.flush
        end
        writer.write(Marshal.dump(success))
        writer.close
        exit!(true)
      end
      writer.close
      [pid, reader, stdout_file, stderr_file]
    end

    success = T.let(true, T::Boolean)
    workers.each do |pid, reader, stdout_file, stderr_file|
      worker_success = begin
        # The data being loaded was written by our own forked child process.
        Marshal.load(reader) # rubocop:disable Security/MarshalLoad
      rescue EOFError
        nil
      end
      reader.close
      Process.wait(pid)

      [stdout_file, stderr_file].each(&:rewind)
      $stdout.print stdout_file.read
      $stderr.print stderr_file.read
      [stdout_file, stderr_file].each(&:close!)

      case worker_success
      when nil
        onoe "readall worker exited unexpectedly!"
        success = false
      when false
        success = false
      end
    end
    success
  end
end

require "extend/os/readall"
