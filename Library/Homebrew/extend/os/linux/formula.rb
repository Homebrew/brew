# typed: true # This cannot be `# typed: strict` due to the use of `undef`.
# frozen_string_literal: true

class Formula
  undef shared_library
  undef loader_path
  undef deuniversalize_machos
  undef add_global_deps_to_spec
  undef valid_platform?

  sig { params(name: String, version: T.nilable(T.any(String, Integer))).returns(String) }
  def shared_library(name, version = nil)
    suffix = if version == "*" || (name == "*" && version.blank?)
      "{,.*}"
    elsif version.present?
      ".#{version}"
    end
    "#{name}.so#{suffix}"
  end

  sig { returns(String) }
  def loader_path
    "$ORIGIN"
  end

  sig { params(targets: T.nilable(T.any(Pathname, String))).void }
  def deuniversalize_machos(*targets); end

  sig { params(spec: SoftwareSpec).void }
  def add_global_deps_to_spec(spec)
    return unless DevelopmentTools.needs_build_formulae?

    @global_deps ||= begin
      dependency_collector = spec.dependency_collector
      related_formula_names = Set.new([
        name,
        *aliases,
        *versioned_formulae_names,
      ])
      [
        dependency_collector.gcc_dep_if_needed(related_formula_names),
        dependency_collector.glibc_dep_if_needed(related_formula_names),
      ].compact.freeze
    end
    @global_deps.each { |dep| spec.dependency_collector.add(dep) }
  end

  sig { returns(T::Boolean) }
  def valid_platform?
    requirements.none?(MacOSRequirement)
  end
end
