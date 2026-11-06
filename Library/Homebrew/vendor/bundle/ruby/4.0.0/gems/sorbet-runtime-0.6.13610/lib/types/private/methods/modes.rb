# frozen_string_literal: true
# typed: true

module T::Private::Methods::Modes
  def self.standard
    'standard'
  end
  def self.abstract
    'abstract'
  end
  def self.overridable
    'overridable'
  end
  def self.override
    'override'
  end
  def self.overridable_override
    'overridable_override'
  end
  def self.untyped
    'untyped'
  end
  MODES = [self.standard, self.abstract, self.overridable, self.override, self.overridable_override, self.untyped].freeze

  OVERRIDABLE_MODES = [self.override, self.overridable, self.overridable_override, self.untyped, self.abstract].freeze
  OVERRIDE_MODES = [self.override, self.overridable_override].freeze
  NON_OVERRIDE_MODES = MODES - OVERRIDE_MODES
end
