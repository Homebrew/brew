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
