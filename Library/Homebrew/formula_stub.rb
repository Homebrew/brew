# typed: strict
# frozen_string_literal: true

class FormulaStub < Formula
  class StubError < NotImplementedError
    sig { override.params(message: BasicObject).void }
    def initialize(message = nil)
      message ||= "Must use the fully loaded formula!"
      super
    end
  end

  sig { void }
  def desc = raise_stub_error

  sig { void }
  def homepage = raise_stub_error

  sig { void }
  def license = raise_stub_error

  sig { void }
  def url = raise_stub_error

  private

  sig { void }
  def raise_stub_error = raise StubError
end
