# typed: strict
# frozen_string_literal: true

require "formula"
require "cask/cask_loader"
require "system_command"

# Helper module for validating syntax in taps.
module Readall
  extend Cachable
  extend SystemCommand::Mixin

  # TODO: remove this once the `MacOS` module is undefined on Linux
  MACOS_MODULE_REGEX = /\b(MacOS|OS::Mac)(\.|::)\b/
  private_constant :MACOS_MODULE_REGEX

  private_class_method :cache

  sig { params(ruby_files: T::Array[Pathname]).returns(T::Boolean) }
  def self.valid_ruby_syntax?(ruby_files)
    failed = T.let(false, T::Boolean)
    ruby_files.each do |ruby_file|
      # As a side effect, print syntax errors/warnings to `$stderr`.
      failed = true if syntax_errors_or_warnings?(ruby_file)
    end
    !failed
  end

  sig { params(alias_dir: Pathname, formula_dir: Pathname).returns(T::Boolean) }
  def self.valid_aliases?(alias_dir, formula_dir)
    return true unless alias_dir.directory?

    failed = T.let(false, T::Boolean)
    alias_dir.each_child do |f|
      if !f.symlink?
        onoe "Non-symlink alias: #{f}"
        failed = true
      elsif !f.file?
        onoe "Non-file alias: #{f}"
        failed = true
      end

      if formula_dir.glob("**/#{f.basename}.rb").any?(&:exist?)
        onoe "Formula duplicating alias: #{f}"
        failed = true
      end
    end
    !failed
  end

  sig { params(tap: Tap, bottle_tag: T.nilable(Utils::Bottles::Tag)).returns(T::Boolean) }
  def self.valid_formulae?(tap, bottle_tag: nil)
    cache[:valid_formulae] ||= {}

    success = T.let(true, T::Boolean)
    tap.formula_files.each do |file|
      valid = cache[:valid_formulae][file]
      next if valid == true || valid&.include?(bottle_tag)

      formula_name = file.basename(".rb").to_s
      formula_contents = file.read.force_encoding("UTF-8")

      readall_namespace = "ReadallNamespace"
      readall_formula_class = Formulary.load_formula(formula_name, file, formula_contents, readall_namespace,
                                                     flags: [], ignore_errors: false)
      readall_formula = readall_formula_class.new(formula_name, file, :stable, tap:)
      readall_formula.to_hash
      # TODO: Remove check for MACOS_MODULE_REGEX once the `MacOS` module is undefined on Linux
      cache[:valid_formulae][file] = if readall_formula.on_system_blocks_exist? ||
                                        formula_contents.match?(MACOS_MODULE_REGEX)
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

  sig { params(_tap: Tap, os_name: T.nilable(Symbol), arch: T.nilable(Symbol)).returns(T::Boolean) }
  def self.valid_casks?(_tap, os_name: nil, arch: nil)
    true
  end

  sig {
    params(
      tap: Tap, aliases: T::Boolean, no_simulate: T::Boolean, os_arch_combinations: T::Array[T::Array[String]],
    ).returns(T::Boolean)
  }
  def self.valid_tap?(tap, aliases: false, no_simulate: false,
                      os_arch_combinations: OnSystem::ALL_OS_ARCH_COMBINATIONS)
    success = true

    if aliases
      valid_aliases = valid_aliases?(tap.alias_dir, tap.formula_dir)
      success = false unless valid_aliases
    end

    if no_simulate
      success = false unless valid_formulae?(tap)
      success = false unless valid_casks?(tap)
    else
      os_arch_combinations.each do |os, arch|
        bottle_tag = Utils::Bottles::Tag.new(system: os, arch:)
        next unless bottle_tag.valid_combination?

        Homebrew::SimulateSystem.with(os:, arch:) do
          success = false unless valid_formulae?(tap, bottle_tag:)
          success = false unless valid_casks?(tap, os_name: os, arch:)
        end
      end
    end

    success
  end

  sig { params(filename: Pathname).returns(T::Boolean) }
  private_class_method def self.syntax_errors_or_warnings?(filename)
    # Retrieve messages about syntax errors/warnings printed to `$stderr`.
    _, err, status = system_command(RUBY_PATH, args: ["-c", "-w", filename], print_stderr: false)

    # Ignore unnecessary warning about named capture conflicts.
    # See https://bugs.ruby-lang.org/issues/12359.
    messages = err.lines
                  .grep_v(/named capture conflicts a local variable/)
                  .join

    $stderr.print messages

    # Only syntax errors result in a non-zero status code. To detect syntax
    # warnings we also need to inspect the output to `$stderr`.
    !status.success? || !messages.chomp.empty?
  end
end

require "extend/os/readall"
