# typed: true # rubocop:disable Sorbet/StrictSigil
# frozen_string_literal: true

module OS
  module Mac
    module DependencyCollector
      def git_dep_if_needed(tags); end

      def subversion_dep_if_needed(tags)
        Dependency.new("subversion", [*tags, :implicit])
      end

      def cvs_dep_if_needed(tags)
        Dependency.new("cvs", [*tags, :implicit])
      end

      def xz_dep_if_needed(tags); end

      def unzip_dep_if_needed(tags); end

      def bzip2_dep_if_needed(tags); end
    end
  end
end

DependencyCollector.prepend(OS::Mac::DependencyCollector)
