# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Homebrew
  module VernierForkGuard
    # This file is required before Homebrew's usual command boot has installed
    # the global `sig` helper.
    # rubocop:disable Sorbet/RedundantExtendTSig
    extend T::Sig
    # rubocop:enable Sorbet/RedundantExtendTSig

    sig { params(block: T.nilable(T.proc.returns(T.untyped))).returns(T.untyped) }
    def self.without_running_collector(&block)
      raise ArgumentError, "block required" unless block

      return yield unless Object.const_defined?(:Vernier)

      # `Vernier::Autorun` is created by `-r vernier/autorun`; Sorbet's RBI for
      # the gem does not expose it, so keep this lookup dynamic.
      # rubocop:disable Sorbet/ConstantsFromStrings
      autorun = T.let(Object.const_get(:Vernier).const_get(:Autorun), T.untyped)
      # rubocop:enable Sorbet/ConstantsFromStrings
      return yield unless autorun.running?

      # Vernier registers internal thread hooks and owns native mutexes while the
      # collector is running. Forking with that state active can leave the child
      # process stuck before it reaches exec.
      #
      # Stopping here loses samples taken during fork setup, but that is a better
      # tradeoff than hanging the profiled command. The common process helpers use
      # spawn while `HOMEBREW_SPAWN_SYSTEM` is set, so this remains a fallback.
      autorun.collector.stop
      autorun.collector = nil
      pid = nil
      begin
        pid = yield
      ensure
        # Restart only in the parent. In the child, `yield` returns nil and exec
        # should happen immediately through the original fork path.
        autorun.start if pid && !autorun.running?
      end
      pid
    end

    sig { void }
    def self.stop_running_collector
      return unless Object.const_defined?(:Vernier)

      # `Vernier::Autorun` is absent from the gem's RBI, so look it up dynamically.
      # rubocop:disable Sorbet/ConstantsFromStrings
      autorun = T.let(Object.const_get(:Vernier).const_get(:Autorun), T.untyped)
      # rubocop:enable Sorbet/ConstantsFromStrings
      return unless autorun.running?

      autorun.stop
    end
  end
end

# Keep this monkey-patch local to `brew prof --vernier`: this file is only
# loaded by that command after `vernier/autorun`.
Kernel.module_eval <<~RUBY, __FILE__, __LINE__ + 1
  # These aliases let us wrap direct process replacement paths without changing
  # unrelated command code paths.
  alias_method :homebrew_vernier_fork_guard_fork, :fork
  alias_method :homebrew_vernier_fork_guard_exec, :exec

  def fork(&block)
    Homebrew::VernierForkGuard.without_running_collector do
      homebrew_vernier_fork_guard_fork(&block)
    end
  end

  def exec(...)
    # `brew ruby` reaches here in the profiled process. Stop and write the
    # Vernier result before replacing the process so no SIGPROF state carries
    # into the new executable.
    Homebrew::VernierForkGuard.stop_running_collector
    homebrew_vernier_fork_guard_exec(...)
  end
RUBY
