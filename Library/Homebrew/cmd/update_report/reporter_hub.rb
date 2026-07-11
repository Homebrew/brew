# typed: strict
# frozen_string_literal: true

class ReporterHub
  include Utils::Output::Mixin

  sig { returns(T::Array[Reporter]) }
  attr_reader :reporters

  sig { void }
  def initialize
    @hash = T.let({}, T::Hash[Symbol, T::Array[T.any(String, [String, String])]])
    @reporters = T.let([], T::Array[Reporter])
  end

  sig { params(key: Symbol).returns(T::Array[String]) }
  def select_formula_or_cask(key)
    raise "Unsupported key #{key}" unless [:A, :AC, :D, :DC, :M, :MC, :R, :RC, :T].include?(key)

    T.cast(@hash.fetch(key, []), T::Array[String])
  end

  sig { params(reporter: Reporter, auto_update: T::Boolean).void }
  def add(reporter, auto_update: false)
    @reporters << reporter
    report = reporter.report(auto_update:).reject { |_k, v| v.empty? }
    @hash.update(report) { |_key, oldval, newval| oldval + newval }
  end

  sig { returns(T::Boolean) }
  def empty?
    @hash.empty?
  end

  sig { params(auto_update: T::Boolean).void }
  def dump(auto_update: false)
    unless Homebrew::EnvConfig.no_update_report_new?
      dump_new_formula_report
      dump_new_cask_report
    end

    dump_deleted_formula_report
    dump_deleted_cask_report

    outdated_formulae = Formula.installed.select(&:outdated?).map(&:name)
    outdated_casks = Cask::Caskroom.casks.select(&:outdated?).map(&:token)
    unless auto_update
      output_dump_formula_or_cask_report "Outdated Formulae", outdated_formulae
      output_dump_formula_or_cask_report "Outdated Casks", outdated_casks
    end
    return if outdated_formulae.blank? && outdated_casks.blank?

    outdated_formulae = outdated_formulae.count
    outdated_casks = outdated_casks.count

    update_pronoun = if (outdated_formulae + outdated_casks) == 1
      "it"
    else
      "them"
    end

    msg = ""

    if outdated_formulae.positive?
      noun = Utils.pluralize("formula", outdated_formulae)
      msg += "#{Tty.bold}#{outdated_formulae}#{Tty.reset} outdated #{noun}"
    end

    if outdated_casks.positive?
      msg += " and " if msg.present?
      msg += "#{Tty.bold}#{outdated_casks}#{Tty.reset} outdated #{Utils.pluralize("cask", outdated_casks)}"
    end

    return if msg.blank?

    # When auto-updating before a zero-argument `brew upgrade` or `brew outdated`,
    # that command lists the outdated packages itself so don't duplicate it here.
    # Two-way sync: `auto-update` in `Library/Homebrew/brew.sh`.
    return if auto_update && ENV["HOMEBREW_AUTO_UPDATE_SKIP_OUTDATED"].present?

    puts
    puts "You have #{msg} installed."
    # If we're auto-updating, don't need to suggest commands that we're perhaps
    # already running.
    return if auto_update

    puts <<~EOS
      You can upgrade #{update_pronoun} with #{Tty.bold}brew upgrade#{Tty.reset}
      or list #{update_pronoun} with #{Tty.bold}brew outdated#{Tty.reset}.
    EOS
  end

  private

  sig { void }
  def dump_new_formula_report
    formulae = select_formula_or_cask(:A).sort.reject { |name| installed?(name) }
    return if formulae.blank?

    ohai "New Formulae"
    should_display_descriptions = if Homebrew::EnvConfig.no_install_from_api?
      formulae.size <= 100
    else
      true
    end
    items = formulae.map do |formula|
      if should_display_descriptions && (desc = description(formula))
        [formula, desc]
      else
        [formula, ""]
      end
    end
    print_table(items)
  end

  sig { void }
  def dump_new_cask_report
    return unless Cask::Caskroom.any_casks_installed?

    casks = select_formula_or_cask(:AC).sort.reject { |name| cask_installed?(name) }
    return if casks.blank?

    ohai "New Casks"
    should_display_descriptions = if Homebrew::EnvConfig.no_install_from_api?
      casks.size <= 100
    else
      true
    end
    items = casks.map do |cask|
      cask_token = Utils.name_from_full_name(cask)
      if should_display_descriptions && (desc = cask_description(cask))
        [cask_token, desc]
      else
        [cask_token, ""]
      end
    end
    print_table(items)
  end

  sig { void }
  def dump_deleted_formula_report
    formulae = select_formula_or_cask(:D).sort.filter_map do |name|
      pretty_uninstalled(name) if installed?(name)
    end

    output_dump_formula_or_cask_report "Deleted Installed Formulae", formulae
  end

  sig { void }
  def dump_deleted_cask_report
    return if Homebrew::SimulateSystem.simulating_or_running_on_linux?

    casks = select_formula_or_cask(:DC).sort.filter_map do |name|
      name = Utils.name_from_full_name(name)
      pretty_uninstalled(name) if cask_installed?(name)
    end

    output_dump_formula_or_cask_report "Deleted Installed Casks", casks
  end

  sig { params(title: String, formulae_or_casks: T::Array[String]).void }
  def output_dump_formula_or_cask_report(title, formulae_or_casks)
    return if formulae_or_casks.blank?

    ohai title, Formatter.columns(formulae_or_casks.sort)
  end

  sig { params(formula: String).returns(T::Boolean) }
  def installed?(formula)
    (HOMEBREW_CELLAR/Utils.name_from_full_name(formula)).directory?
  end

  sig { params(cask: String).returns(T::Boolean) }
  def cask_installed?(cask)
    (Cask::Caskroom.path/cask).directory?
  end

  sig { returns(T::Array[T.untyped]) }
  def all_formula_json
    return @all_formula_json if @all_formula_json

    @all_formula_json = T.let(nil, T.nilable(T::Array[T.untyped]))
    all_formula_json, = Homebrew::API.fetch_json_api_file "formula.jws.json"
    all_formula_json = T.cast(all_formula_json, T::Array[T.untyped])
    @all_formula_json = all_formula_json
  end

  sig { returns(T::Array[T.untyped]) }
  def all_cask_json
    return @all_cask_json if @all_cask_json

    @all_cask_json = T.let(nil, T.nilable(T::Array[T.untyped]))
    all_cask_json, = Homebrew::API.fetch_json_api_file "cask.jws.json"
    all_cask_json = T.cast(all_cask_json, T::Array[T.untyped])
    @all_cask_json = all_cask_json
  end

  sig { params(formula: String).returns(T.nilable(String)) }
  def description(formula)
    if Homebrew::EnvConfig.no_install_from_api?
      # Skip non-homebrew/core formulae for security.
      return if formula.include?("/")

      begin
        Formula[formula].desc&.presence
      rescue FormulaUnavailableError
        nil
      end
    else
      all_formula_json.find { |f| f["name"] == formula }
                      &.fetch("desc", nil)
                      &.presence
    end
  end

  sig { params(cask: String).returns(T.nilable(String)) }
  def cask_description(cask)
    if Homebrew::EnvConfig.no_install_from_api?
      # Skip non-homebrew/cask formulae for security.
      return if cask.include?("/")

      begin
        Cask::CaskLoader.load(cask).desc&.presence
      rescue Cask::CaskError
        nil
      end
    else
      all_cask_json.find { |f| f["token"] == cask }
                   &.fetch("desc", nil)
                   &.presence
    end
  end

  sig { params(items: T::Array[[String, String]]).void }
  def print_table(items)
    return if items.blank?

    name_width = (items.map { |name, _| name.length }.max || 0) + 2
    items.each do |name, desc|
      if desc.present?
        puts format("%-#{name_width}s %s", name, desc)
      else
        puts name
      end
    end
  end
end
