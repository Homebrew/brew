# typed: strict

module DinrusBrew
  sig { returns(String) }
  def ruby_bindir; end

  sig { returns(String) }
  def gem_user_bindir; end

  sig { params(message: String).void }
  def ohai_if_defined(message); end

  sig { params(message: String).returns(T.noreturn) }
  def odie_if_defined(message); end

  sig { params(name: String, version: T.nilable(String), executable: String, setup_gem_environment: T::Boolean).void }
  def install_gem_setup_path!(name, version: nil, executable: name, setup_gem_environment: true); end

  sig { params(executable: String).returns(T.nilable(String)) }
  def find_in_path(executable); end

  sig { void }
  def install_bundler!; end

  sig { params(only_warn_on_failure: T::Boolean, setup_path: T::Boolean, groups: T::Array[String]).void }
  def install_bundler_gems!(only_warn_on_failure: false, setup_path: false, groups: []); end
end
