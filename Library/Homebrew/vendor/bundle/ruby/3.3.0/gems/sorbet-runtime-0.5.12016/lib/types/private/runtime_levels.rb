# frozen_string_literal: true
# typed: true

# Used in `sig.checked(level)` to determine when runtime type checking
# is enabled on a method.
module T::Private::RuntimeLevels
  LEVELS = [
    # Validate every call in every environment
    :always,
    # Validate in tests, but not in production
    :tests,
    # Don't even validate in tests, b/c too expensive,
    # or b/c we fully trust the static typing
    :never,
  ].freeze

  @check_tests = false
  @wrapped_tests_with_validation = false

  @has_read_default_checked_level = false
  @default_checked_level = :always

  def self.check_tests?
    # Assume that this code path means that some `sig.checked(:tests)`
    # has been wrapped (or not wrapped) already, which is a trapdoor
    # for toggling `@check_tests`.
    @wrapped_tests_with_validation = true

    @check_tests
  end

  def self.enable_checking_in_tests
    if !@check_tests && @wrapped_tests_with_validation
      all_checked_tests_sigs = T::Private::Methods.all_checked_tests_sigs
      locations = all_checked_tests_sigs.map {|sig| sig.method.source_location.join(':')}.join("\n- ")
      raise "Toggle `:tests`-level runtime type checking earlier. " \
        "There are already some methods wrapped with `sig.checked(:tests)`:\n" \
        "- #{locations}"
    end

    _toggle_checking_tests(true)
  end

  def self.default_checked_level
    @has_read_default_checked_level = true
    @default_checked_level
  end

  def self.default_checked_level=(default_checked_level)
    if @has_read_default_checked_level
      raise "Set the default checked level earlier. There are already some methods whose sig blocks have evaluated which would not be affected by the new default."
    end
    if !LEVELS.include?(default_checked_level)
      raise "Invalid `checked` level '#{default_checked_level}'. Use one of: #{LEVELS}."
    end

    @default_checked_level = default_checked_level
  end

  def self._toggle_checking_tests(checked)
    @check_tests = checked
  end

  private_class_method def self.set_enable_checking_in_tests_from_environment
    if ENV['SORBET_RUNTIME_ENABLE_CHECKING_IN_TESTS']
      enable_checking_in_tests
    end
  end
  set_enable_checking_in_tests_from_environment

  private_class_method def self.set_default_checked_level_from_environment
    level = ENV['SORBET_RUNTIME_DEFAULT_CHECKED_LEVEL']
    if level
      self.default_checked_level = level.to_sym
    end
  end
  set_default_checked_level_from_environment
end
