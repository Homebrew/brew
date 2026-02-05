# typed: true

# DO NOT EDIT MANUALLY
# This file was pulled from a central RBI files repository.
# Please run `bin/tapioca annotations` to update it.

module Rainbow
  # @shim: https://github.com/sickill/rainbow/blob/master/lib/rainbow.rb#L10-L12
  sig { returns(T::Boolean) }
  attr_accessor :enabled

  class Color
    sig { returns(Symbol) }
    attr_reader :ground

    sig { params(ground: Symbol, values: T.any([Integer], [Integer, Integer, Integer])).returns(Color) }
    def self.build(ground, values); end

    sig { params(hex: String).returns([Integer, Integer, Integer]) }
    def self.parse_hex_color(hex); end

    class Indexed < Rainbow::Color
      sig { returns(Integer) }
      attr_reader :num

      sig { params(ground: Symbol, num: Integer).void }
      def initialize(ground, num); end

      sig { returns(T::Array[Integer]) }
      def codes; end
    end

    class Named < Rainbow::Color::Indexed
      NAMES = T.let(nil, T::Hash[Symbol, Integer])

      sig { params(ground: Symbol, name: Symbol).void }
      def initialize(ground, name); end

      sig { returns(T::Array[Symbol]) }
      def self.color_names; end

      sig { returns(String) }
      def self.valid_names; end
    end

    class RGB < Rainbow::Color::Indexed
      sig { returns(Integer) }
      attr_reader :r, :g, :b

      sig { params(ground: Symbol, values: Integer).void }
      def initialize(ground, *values); end

      sig { returns(T::Array[Integer]) }
      def codes; end

      sig { params(value: Numeric).returns(Integer) }
      def self.to_ansi_domain(value); end
    end

    class X11Named < Rainbow::Color::RGB
      include Rainbow::X11ColorNames

      sig { params(ground: Symbol, name: Symbol).void }
      def initialize(ground, name); end

      sig { returns(T::Array[Symbol]) }
      def self.color_names; end

      sig { returns(String) }
      def self.valid_names; end
    end
  end

  sig { returns(Wrapper) }
  def self.global; end

  sig { returns(T::Boolean) }
  def self.enabled; end

  sig { params(value: T::Boolean).returns(T::Boolean) }
  def self.enabled=(value); end

  sig { params(string: String).returns(String) }
  def self.uncolor(string); end

  class NullPresenter < String
    sig { params(values: T.any([Integer], [Integer, Integer, Integer])).returns(NullPresenter) }
    def color(*values); end

    sig { params(values: T.any([Integer], [Integer, Integer, Integer])).returns(NullPresenter) }
    def foreground(*values); end

    sig { params(values: T.any([Integer], [Integer, Integer, Integer])).returns(NullPresenter) }
    def fg(*values); end

    sig { params(values: T.any([Integer], [Integer, Integer, Integer])).returns(NullPresenter) }
    def background(*values); end

    sig { params(values: T.any([Integer], [Integer, Integer, Integer])).returns(NullPresenter) }
    def bg(*values); end

    sig { returns(NullPresenter) }
    def reset; end

    sig { returns(NullPresenter) }
    def bright; end

    sig { returns(NullPresenter) }
    def faint; end

    sig { returns(NullPresenter) }
    def italic; end

    sig { returns(NullPresenter) }
    def underline; end

    sig { returns(NullPresenter) }
    def blink; end

    sig { returns(NullPresenter) }
    def inverse; end

    sig { returns(NullPresenter) }
    def hide; end

    sig { returns(NullPresenter) }
    def cross_out; end

    sig { returns(NullPresenter) }
    def black; end

    sig { returns(NullPresenter) }
    def red; end

    sig { returns(NullPresenter) }
    def green; end

    sig { returns(NullPresenter) }
    def yellow; end

    sig { returns(NullPresenter) }
    def blue; end

    sig { returns(NullPresenter) }
    def magenta; end

    sig { returns(NullPresenter) }
    def cyan; end

    sig { returns(NullPresenter) }
    def white; end

    sig { returns(NullPresenter) }
    def bold; end

    sig { returns(NullPresenter) }
    def dark; end

    sig { returns(NullPresenter) }
    def strike; end
  end

  class Presenter < String
    TERM_EFFECTS = T.let(nil, T::Hash[Symbol, Integer])

    sig { params(values: T.any([Integer], [Integer, Integer, Integer])).returns(Presenter) }
    def color(*values); end

    sig { params(values: T.any([Integer], [Integer, Integer, Integer])).returns(Presenter) }
    def foreground(*values); end

    sig { params(values: T.any([Integer], [Integer, Integer, Integer])).returns(Presenter) }
    def fg(*values); end

    sig { params(values: T.any([Integer], [Integer, Integer, Integer])).returns(Presenter) }
    def background(*values); end

    sig { params(values: T.any([Integer], [Integer, Integer, Integer])).returns(Presenter) }
    def bg(*values); end

    sig { returns(Presenter) }
    def reset; end

    sig { returns(Presenter) }
    def bright; end

    sig { returns(Presenter) }
    def faint; end

    sig { returns(Presenter) }
    def italic; end

    sig { returns(Presenter) }
    def underline; end

    sig { returns(Presenter) }
    def blink; end

    sig { returns(Presenter) }
    def inverse; end

    sig { returns(Presenter) }
    def hide; end

    sig { returns(Presenter) }
    def cross_out; end

    sig { returns(Presenter) }
    def black; end

    sig { returns(Presenter) }
    def red; end

    sig { returns(Presenter) }
    def green; end

    sig { returns(Presenter) }
    def yellow; end

    sig { returns(Presenter) }
    def blue; end

    sig { returns(Presenter) }
    def magenta; end

    sig { returns(Presenter) }
    def cyan; end

    sig { returns(Presenter) }
    def white; end

    sig { returns(Presenter) }
    def bold; end

    sig { returns(Presenter) }
    def dark; end

    sig { returns(Presenter) }
    def strike; end
  end

  class StringUtils
    sig { params(string: String, codes: T::Array[Integer]).returns(String) }
    def self.wrap_with_sgr(string, codes); end

    sig { params(string: String).returns(String) }
    def self.uncolor(string); end
  end

  VERSION = T.let(nil, String)

  class Wrapper
    sig { returns(T::Boolean) }
    attr_accessor :enabled

    sig { params(enabled: T::Boolean).void }
    def initialize(enabled = true); end

    sig { params(string: String).returns(T.any(Rainbow::Presenter, Rainbow::NullPresenter)) }
    def wrap(string); end
  end

  module X11ColorNames
    NAMES = T.let(nil, T::Hash[Symbol, [Integer, Integer, Integer]])
  end
end

sig { params(string: String).returns(Rainbow::Presenter) }
def Rainbow(string); end
