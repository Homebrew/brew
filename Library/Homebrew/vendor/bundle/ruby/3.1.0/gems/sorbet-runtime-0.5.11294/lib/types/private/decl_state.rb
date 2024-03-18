# frozen_string_literal: true
# typed: true

class T::Private::DeclState
  def self.current
    Thread.current[:opus_types__decl_state] ||= self.new
  end

  def self.current=(other)
    Thread.current[:opus_types__decl_state] = other
  end

  attr_accessor :active_declaration
  attr_accessor :skip_on_method_added

  def reset!
    self.active_declaration = nil
  end

  def without_on_method_added
    begin
      # explicit 'self' is needed here
      old_value = self.skip_on_method_added
      self.skip_on_method_added = true
      yield
    ensure
      self.skip_on_method_added = old_value
    end
  end
end
