# typed: true
# frozen_string_literal: true

# Representation of a `*PATH` environment variable.
#
# @api private
class PATH
  include Enumerable
  extend Forwardable

  delegate each: :@paths

  # FIXME: Enable cop again when https://github.com/sorbet/sorbet/issues/3532 is fixed.
  # rubocop:disable Style/MutableConstant
  Element = T.type_alias { T.nilable(T.any(Pathname, String, PATH)) }
  private_constant :Element
  Elements = T.type_alias { T.any(Element, T::Array[Element]) }
  private_constant :Elements
  # rubocop:enable Style/MutableConstant

  sig { params(paths: Elements).void }
  def initialize(*paths)
    @paths = parse(paths)
  end

  sig { params(paths: Elements).returns(T.self_type) }
  def prepend(*paths)
    @paths = parse(paths + @paths)
    self
  end

  sig { params(paths: Elements).returns(T.self_type) }
  def append(*paths)
    @paths = parse(@paths + paths)
    self
  end

  sig { params(index: Integer, paths: Elements).returns(T.self_type) }
  def insert(index, *paths)
    @paths = parse(@paths.insert(index, *paths))
    self
  end

  sig { params(block: T.proc.params(arg0: String).returns(T::Boolean)).returns(T.self_type) }
  def select(&block)
    self.class.new(@paths.select(&block))
  end

  sig { params(block: T.proc.params(arg0: String).returns(T::Boolean)).returns(T.self_type) }
  def reject(&block)
    self.class.new(@paths.reject(&block))
  end

  sig { returns(T::Array[String]) }
  def to_ary
    @paths.dup.to_ary
  end
  alias to_a to_ary

  sig { returns(String) }
  def to_str
    @paths.join(File::PATH_SEPARATOR)
  end
  alias to_s to_str

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
    (other.respond_to?(:to_ary) && to_ary == other.to_ary) ||
      (other.respond_to?(:to_str) && to_str == other.to_str) ||
      false
  end

  sig { returns(T::Boolean) }
  def empty?
    @paths.empty?
  end

  sig { returns(T.nilable(T.self_type)) }
  def existing
    existing_path = select(&File.method(:directory?))
    # return nil instead of empty PATH, to unset environment variables
    existing_path unless existing_path.empty?
  end

  private

  sig { params(paths: T::Array[Elements]).returns(T::Array[String]) }
  def parse(paths)
    paths.flatten
         .compact
         .flat_map { |p| Pathname(p).to_path.split(File::PATH_SEPARATOR) }
         .uniq
  end
end
