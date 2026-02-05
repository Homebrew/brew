# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Homebrew
  module TestBot
    class BottlesFetch < TestFormulae
      attr_accessor :testing_formulae

      def run!(args:)
        info_header "Testing formulae:"
        puts testing_formulae
        puts

        formulae_by_tag.each do |tag, formulae|
          fetch_bottles!(tag, formulae, args:)
          puts
        end
      end

      private

      def formulae_by_tag
        tags = Hash.new { |hash, key| hash[key] = Set.new }

        testing_formulae.each do |formula_name|
          formula = Formula[formula_name]
          next if formula.disabled?

          formula_tags = formula.bottle_specification.collector.tags

          odie "#{formula_name} is missing bottles! Did you mean to use `brew pr-publish`?" if formula_tags.blank?

          formula_tags.each do |tag|
            tags[tag] << formula_name
          end
        end

        tags
      end

      def fetch_bottles!(tag, formulae, args:)
        test_header(:BottlesFetch, method: "fetch_bottles!(#{tag})")

        cleanup_during!(args:)
        test "brew", "fetch", "--retry", "--formulae", "--bottle-tag=#{tag}", *formulae
      end
    end
  end
end
