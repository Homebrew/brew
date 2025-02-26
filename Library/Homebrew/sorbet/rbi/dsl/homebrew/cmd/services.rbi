# typed: strict

class Homebrew::Cmd::Services
  sig { returns(Homebrew::Cmd::Services::Args) }
  def args; end
end

class Homebrew::Cmd::Services::Args < Homebrew::CLI::Args
  sig { returns(T::Boolean) }
  def all?; end

  sig { returns(T.nilable(String)) }
  def file; end

  sig { returns(T::Boolean) }
  def json?; end

  sig { returns(T::Boolean) }
  def non_bundler_gems?; end

  sig { returns(T::Boolean) }
  def no_wait?; end

  sig { returns(T.nilable(String)) }
  def sudo_service_user; end

  sig { returns(T.nilable(String)) }
  def max_wait; end
end
