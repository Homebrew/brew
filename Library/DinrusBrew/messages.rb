# typed: strict
# frozen_string_literal: true

# A {Messages} object collects messages that may need to be displayed together
# at the end of a multi-step `brew` command run.
class Messages
  sig { returns(T::Array[T::Hash[Symbol, Symbol]]) }
  attr_reader :caveats

  sig { returns(Integer) }
  attr_reader :package_count

  sig { returns(T::Array[T::Hash[String, Float]]) }
  attr_reader :install_times

  sig { void }
  def initialize
    @caveats = T.let([], T::Array[T::Hash[Symbol, Symbol]])
    @package_count = T.let(0, Integer)
    @install_times = T.let([], T::Array[T::Hash[String, Float]])
  end

  sig { params(package: String, caveats: T.any(String, Caveats)).void }
  def record_caveats(package, caveats)
    @caveats.push(package:, caveats:)
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
    return if @package_count == 1 && !force
    return if @caveats.empty?

    oh1 "Caveats"
    @caveats.each do |c|
      ohai c[:package], c[:caveats]
    end
  end

  sig { void }
  def display_install_times
    return if install_times.empty?

    oh1 "Элементы установки"
    install_times.each do |t|
      puts format("%<package>-20с %<time>10.3f с", t)
    end
  end
end
