# typed: strict
# frozen_string_literal: true

require "utils/output"

# A {Messages} object collects messages that may need to be displayed together
# at the end of a multi-step `brew` command run.
class Messages
  include ::Utils::Output::Mixin

  sig { returns(T::Array[{ package: String, caveats: T.any(String, Caveats) }]) }
  attr_reader :caveats

  sig { returns(Integer) }
  attr_reader :package_count

  sig { returns(T::Array[{ package: String, time: Float }]) }
  attr_reader :install_times

  sig { void }
  def initialize
    @caveats = T.let([], T::Array[{ package: String, caveats: T.any(String, Caveats) }])
    @completions_and_elisp = T.let(Set.new, T::Set[String])
    @package_count = T.let(0, Integer)
    @install_times = T.let([], T::Array[{ package: String, time: Float }])
  end

  sig { params(package: String, caveats: T.any(String, Caveats)).void }
  def record_caveats(package, caveats)
    @caveats.push(package:, caveats:)
  end

  sig { params(completions_and_elisp: T::Array[String]).void }
  def record_completions_and_elisp(completions_and_elisp)
    @completions_and_elisp.merge(completions_and_elisp)
  end

  sig { params(package: String, elapsed_time: Float).void }
  def package_installed(package, elapsed_time)
    @package_count += 1
    @install_times.push(package:, time: elapsed_time)
  end

  sig { params(force_caveats: T::Boolean, display_times: T::Boolean).void }
  def display_messages(force_caveats: false, display_times: false)
    display_caveats(force: force_caveats)
    display_install_times if display_times
  end

  sig { params(force: T::Boolean).void }
  def display_caveats(force: false)
    return if @package_count.zero?
    return if @caveats.empty? && @completions_and_elisp.empty?

    oh1 "Caveats" unless @completions_and_elisp.empty?
    @completions_and_elisp.each { |c| puts c }
    return if @package_count == 1 && !force

    oh1 "Caveats" if @completions_and_elisp.empty?
    @caveats.each { |c| ohai c.fetch(:package), c.fetch(:caveats) }
  end

  sig { void }
  def display_install_times
    return if install_times.empty?

    oh1 "Installation times"
    install_times.each do |t|
      puts format("%<package>-20s %<time>10.3f s", t)
    end
  end
end
