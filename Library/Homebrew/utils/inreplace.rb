# typed: true
# frozen_string_literal: true

require "utils/string_inreplace_extension"

module Utils
  # Helper functions for replacing text in files in-place.
  #
  # @api private
  module Inreplace
    # Error during text replacement.
    class Error < RuntimeError
      def initialize(errors)
        formatted_errors = errors.reduce(+"inreplace failed\n") do |s, (path, errs)|
          s << "#{path}:\n" << errs.map { |e| "  #{e}\n" }.join
        end
        super formatted_errors.freeze
      end
    end

    # Sometimes we have to change a bit before we install. Mostly we
    # prefer a patch, but if you need the {Formula#prefix prefix} of
    # this formula in the patch you have to resort to `inreplace`,
    # because in the patch you don't have access to any variables
    # defined by the formula, as only `HOMEBREW_PREFIX` is available
    # in the {DATAPatch embedded patch}.
    #
    # @example `inreplace` supports regular expressions:
    #   inreplace "somefile.cfg", /look[for]what?/, "replace by #{bin}/tool"
    #
    # @example `inreplace` supports blocks:
    #   inreplace "Makefile" do |s|
    #     s.gsub! "/usr/local", HOMEBREW_PREFIX.to_s
    #   end
    #
    # @see StringInreplaceExtension
    # @api public
    sig {
      params(
        paths:        T.any(T::Enumerable[T.any(String, Pathname)], String, Pathname),
        before:       T.nilable(T.any(Pathname, Regexp, String)),
        after:        T.nilable(T.any(Pathname, String, Symbol)),
        audit_result: T::Boolean,
        block:        T.nilable(T.proc.params(s: StringInreplaceExtension).void),
      ).void
    }
    def self.inreplace(paths, before = nil, after = nil, audit_result: true, &block)
      paths = Array(paths)
      after &&= after.to_s
      before = before.to_s if before.is_a?(Pathname)

      errors = {}

      errors["`paths` (first) parameter"] = ["`paths` was empty"] if paths.all?(&:blank?)

      paths.each do |path|
        str = File.binread(path)
        s = StringInreplaceExtension.new(str)

        if before.nil? && after.nil?
          raise ArgumentError, "Must supply a block or before/after params" unless block

          yield s
        else
          s.gsub!(T.must(before), T.must(after), audit_result)
        end

        errors[path] = s.errors unless s.errors.empty?

        Pathname(path).atomic_write(s.inreplace_string)
      end

      raise Utils::Inreplace::Error, errors if errors.present?
    end

    # @api private
    def self.inreplace_pairs(path, replacement_pairs, read_only_run: false, silent: false)
      str = File.binread(path)
      contents = StringInreplaceExtension.new(str)
      replacement_pairs.each do |old, new|
        ohai "replace #{old.inspect} with #{new.inspect}" unless silent
        unless old
          contents.errors << "No old value for new value #{new}! Did you pass the wrong arguments?"
          next
        end

        contents.gsub!(old, new)
      end
      raise Utils::Inreplace::Error, path => contents.errors if contents.errors.present?

      Pathname(path).atomic_write(contents.inreplace_string) unless read_only_run
      contents.inreplace_string
    end
  end
end
