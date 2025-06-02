# frozen_string_literal: true

class Gem::UnknownCommandSpellChecker
  attr_reader :error

  def initialize(error)
    @error = error
  end

  def corrections
    @corrections ||=
      spell_checker.correct(error.unknown_command).map(&:inspect)
  end

  private

  def spell_checker
    dictionary = Gem::CommandManager.instance.command_names
    DidYouMean::SpellChecker.new(dictionary: dictionary)
  end
end
