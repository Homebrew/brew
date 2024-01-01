# typed: true
# frozen_string_literal: true

class DependencyCollector
  undef git_dep_if_needed, subversion_dep_if_needed, cvs_dep_if_needed,
        xz_dep_if_needed, unzip_dep_if_needed, bzip2_dep_if_needed

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
