# typed: true

# DO NOT EDIT MANUALLY
# This file was pulled from a central RBI files repository.
# Please run `bin/tapioca annotations` to update it.

module Minitest::Assertions
  sig { params(test: T.anything, msg: T.anything).returns(TrueClass) }
  def assert(test, msg = nil); end

  sig { params(obj: T.anything, msg: T.anything).returns(TrueClass) }
  def assert_empty(obj, msg = nil); end

  sig { params(exp: T.anything, act: T.anything, msg: T.anything).returns(TrueClass) }
  def assert_equal(exp, act, msg = nil); end

  sig { params(exp: T.anything, act: T.anything, delta: Numeric, msg: T.anything).returns(TrueClass) }
  def assert_in_delta(exp, act, delta = T.unsafe(nil), msg = nil); end

  sig { params(a: T.anything, b: T.anything, epsilon: Numeric, msg: T.anything).returns(TrueClass) }
  def assert_in_epsilon(a, b, epsilon = T.unsafe(nil), msg = nil); end

  sig { params(collection: T.anything, obj: T.anything, msg: T.anything).returns(TrueClass) }
  def assert_includes(collection, obj, msg = nil); end

  sig { params(cls: T.anything, obj: T.anything, msg: T.anything).returns(TrueClass) }
  def assert_instance_of(cls, obj, msg = nil); end

  sig { params(cls: T.anything, obj: T.anything, msg: T.anything).returns(TrueClass) }
  def assert_kind_of(cls, obj, msg = nil); end

  sig { params(matcher: T.any(String, Regexp), obj: T.anything, msg: T.anything).returns(MatchData) }
  def assert_match(matcher, obj, msg = nil); end

  sig { params(obj: T.anything, msg: T.anything).returns(TrueClass) }
  def assert_nil(obj, msg = nil); end

  sig { params(o1: T.anything, op: T.any(Symbol, String), o2: T.anything, msg: T.anything).returns(TrueClass) }
  def assert_operator(o1, op, o2 = T.unsafe(nil), msg = nil); end

  sig { params(stdout: T.nilable(T.any(String, Regexp)), stderr: T.nilable(T.any(String, Regexp)), block: T.proc.void).returns(T::Boolean) }
  def assert_output(stdout = nil, stderr = nil, &block); end

  sig { params(path: T.any(String, Pathname), msg: T.anything).returns(TrueClass) }
  def assert_path_exists(path, msg = nil); end

  sig { params(block: T.proc.void).returns(TrueClass) }
  def assert_pattern(&block); end

  sig { params(o1: T.anything, op: T.any(String, Symbol), msg: T.anything).returns(TrueClass) }
  def assert_predicate(o1, op, msg = nil); end

  sig { params(exp: NilClass, block: T.proc.void).returns(StandardError) }
  sig { type_parameters(:T).params(exp: T.any(T::Class[T.type_parameter(:T)], Regexp, String), block: T.proc.void).returns(T.type_parameter(:T)) }
  def assert_raises(*exp, &block); end

  sig { params(obj: T.anything, meth: T.any(String, Symbol), msg: T.anything, include_all: T::Boolean).returns(TrueClass) }
  def assert_respond_to(obj, meth, msg = nil, include_all: false); end

  sig { params(exp: T.anything, act: T.anything, msg: T.anything).returns(TrueClass) }
  def assert_same(exp, act, msg = nil); end

  sig { params(block: T.proc.void).returns(T::Boolean) }
  def assert_silent(&block); end

  sig { params(sym: Symbol, msg: T.anything, block: T.proc.void).returns(T.anything) }
  def assert_throws(sym, msg = nil, &block); end

  sig { params(test: T.anything, msg: T.anything).returns(TrueClass) }
  def refute(test, msg = nil); end

  sig { params(obj: T.anything, msg: T.anything).returns(TrueClass) }
  def refute_empty(obj, msg = nil); end

  sig { params(exp: T.anything, act: T.anything, msg: T.anything).returns(TrueClass) }
  def refute_equal(exp, act, msg = nil); end

  sig { params(exp: T.anything, act: T.anything, delta: Numeric, msg: T.anything).returns(TrueClass) }
  def refute_in_delta(exp, act, delta = T.unsafe(nil), msg = nil); end

  sig { params(a: T.anything, b: T.anything, epsilon: Numeric, msg: T.anything).returns(TrueClass) }
  def refute_in_epsilon(a, b, epsilon = T.unsafe(nil), msg = nil); end

  sig { params(collection: T.anything, obj: T.anything, msg: T.anything).returns(TrueClass) }
  def refute_includes(collection, obj, msg = nil); end

  sig { params(cls: T.anything, obj: T.anything, msg: T.anything).returns(TrueClass) }
  def refute_instance_of(cls, obj, msg = nil); end

  sig { params(cls: T.anything, obj: T.anything, msg: T.anything).returns(TrueClass) }
  def refute_kind_of(cls, obj, msg = nil); end

  sig { params(matcher: T.any(String, Regexp), obj: T.anything, msg: T.anything).returns(TrueClass) }
  def refute_match(matcher, obj, msg = nil); end

  sig { params(obj: T.anything, msg: T.anything).returns(TrueClass) }
  def refute_nil(obj, msg = nil); end

  sig { params(block: T.proc.void).returns(TrueClass) }
  def refute_pattern(&block); end

  sig { params(o1: T.anything, op: T.any(Symbol, String), o2: T.anything, msg: T.anything).returns(TrueClass) }
  def refute_operator(o1, op, o2 = T.unsafe(nil), msg = nil); end

  sig { params(path: T.any(String, Pathname), msg: T.anything).returns(TrueClass) }
  def refute_path_exists(path, msg = nil); end

  sig { params(o1: T.anything, op: T.any(String, Symbol), msg: T.anything).returns(TrueClass) }
  def refute_predicate(o1, op, msg = nil); end

  sig { params(obj: T.anything, meth: T.any(String, Symbol), msg: T.anything, include_all: T::Boolean).returns(TrueClass) }
  def refute_respond_to(obj, meth, msg = nil, include_all: false); end

  sig { params(exp: T.anything, act: T.anything, msg: T.anything).returns(TrueClass) }
  def refute_same(exp, act, msg = nil); end
end
