# typed: strict
# frozen_string_literal: true

require "context"

module ObserverPathnameExtension
  extend T::Helpers

  requires_ancestor { Pathname }

  class << self
    include Context

    sig { returns(Integer) }
    def n
      @n ||= 0
    end

    sig { params(n: Integer).void }
    attr_writer :n

    sig { returns(Integer) }
    def d
      @d ||= 0
    end

    sig { params(d: Integer).void }
    attr_writer :d

    sig { void }
    def reset_counts!
      @n = T.let(0, T.nilable(Integer))
      @d = T.let(0, T.nilable(Integer))
      @put_verbose_trimmed_warning = T.let(false, T.nilable(T::Boolean))
    end

    sig { returns(Integer) }
    def total
      n + d
    end

    sig { returns([Integer, Integer]) }
    def counts
      [n, d]
    end

    MAXIMUM_VERBOSE_OUTPUT = 100
    private_constant :MAXIMUM_VERBOSE_OUTPUT

    sig { returns(T::Boolean) }
    def verbose?
      return super unless ENV["CI"]
      return false unless super

      if total < MAXIMUM_VERBOSE_OUTPUT
        true
      else
        unless @put_verbose_trimmed_warning
          puts "Only the first #{MAXIMUM_VERBOSE_OUTPUT} operations were output."
          @put_verbose_trimmed_warning = true
        end
        false
      end
    end
  end

  sig { void }
  def unlink
    super
    puts "rm #{self}" if ObserverPathnameExtension.verbose?
    ObserverPathnameExtension.n += 1
  end

  sig { void }
  def mkpath
    super
    puts "mkdir -p #{self}" if ObserverPathnameExtension.verbose?
  end

  sig { void }
  def rmdir
    super
    puts "rmdir #{self}" if ObserverPathnameExtension.verbose?
    ObserverPathnameExtension.d += 1
  end

  sig { params(src: Pathname).void }
  def make_relative_symlink(src)
    super
    puts "ln -s #{src.relative_path_from(dirname)} #{basename}" if ObserverPathnameExtension.verbose?
    ObserverPathnameExtension.n += 1
  end

  sig { void }
  def install_info
    super
    puts "info #{self}" if ObserverPathnameExtension.verbose?
  end

  sig { void }
  def uninstall_info
    super
    puts "uninfo #{self}" if ObserverPathnameExtension.verbose?
  end
end
