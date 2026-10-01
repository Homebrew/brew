# typed: strict
# frozen_string_literal: true

module Test
  module Helper
    # Lets Sorbet see example groups generated from a table, which it cannot do
    # through a plain `each`.
    #
    # @see https://sorbet.org/docs/minitest#table-driven-tests-tests-defined-with-each
    module TestEach
      # `checked(:never)` because `HOMEBREW_SORBET_RECURSIVE` rejects a `Hash` here: it wants a tuple
      # element type, which plain array rows are not. A union instead leaves `U` unbound.
      sig {
        type_parameters(:U).params(
          iter:  T::Enumerable[T.type_parameter(:U)],
          block: T.proc.params(row: T.type_parameter(:U)).void,
        ).void.checked(:never)
      }
      def test_each(iter, &block)
        iter.each(&block)
      end

      sig {
        type_parameters(:K, :V).params(
          hash:  T::Hash[T.type_parameter(:K), T.type_parameter(:V)],
          block: T.proc.params(pair: [T.type_parameter(:K), T.type_parameter(:V)]).void,
        ).void.checked(:never)
      }
      def test_each_hash(hash, &block)
        hash.each(&block)
      end
    end
  end
end
