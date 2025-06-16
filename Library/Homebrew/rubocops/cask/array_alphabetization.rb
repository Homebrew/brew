# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module RuboCop
  module Cop
    module Cask
      class ArrayAlphabetization < Base
        extend AutoCorrector

        sig { params(node: RuboCop::AST::SendNode).void }
        def on_send(node)
          return unless [:zap, :uninstall].include?(node.method_name)

          node.each_descendant(:pair).each do |pair|
            symbols = pair.children.select(&:sym_type?).map(&:value)
            next if symbols.intersect?([:signal, :script, :early_script, :args, :input])

            pair.each_descendant(:array).each do |array|
              if array.children.length == 1
                add_offense(array, message: "Avoid single-element arrays by removing the []") do |corrector|
                  corrector.replace(array.source_range, array.children.first.source)
                end
              end

              next if array.children.length <= 1

              sorted_array = sort_array(array.source.split("\n")).join("\n")

              next if array.source == sorted_array

              add_offense(array, message: "The array elements should be ordered alphabetically") do |corrector|
                corrector.replace(array.source_range, sorted_array)
              end
            end
          end
        end

        def sort_array(source)
          # Combine each comment with the line(s) below so that they remain in the same relative location
          combined_source = source.each_with_index.filter_map do |line, index|
            next if line.blank?
            next if line.strip.start_with?("#")

            next recursively_find_comments(source, index, line)
          end

          # Separate the lines into those that should be sorted and those that should not
          # i.e. skip the opening and closing brackets of the array.
          to_sort, to_keep = combined_source.partition { |line| !line.include?("[") && !line.include?("]") }

          # Sort the lines that should be sorted
          to_sort.sort! do |a, b|
            a_non_comment = a.split("\n").reject { |line| line.strip.start_with?("#") }.first
            b_non_comment = b.split("\n").reject { |line| line.strip.start_with?("#") }.first
            a_non_comment.downcase <=> b_non_comment.downcase
          end

          # Merge the sorted lines and the unsorted lines, preserving the original positions of the unsorted lines
          combined_source.map { |line| to_keep.include?(line) ? line : to_sort.shift }
        end

        def recursively_find_comments(source, index, line)
          if source[index - 1].strip.start_with?("#")
            return recursively_find_comments(source, index - 1, "#{source[index - 1]}\n#{line}")
          end

          line
        end
      end
    end
  end
end
