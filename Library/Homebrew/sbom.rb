# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "cxxstdlib"
require "json"
require "development_tools"
require "cachable"
require "utils/curl"

# Rather than calling `new` directly, use one of the class methods like {SBOM.create}.
class SBOM
  FILENAME = "sbom.spdx.json"
  SCHEMA_FILE = (HOMEBREW_LIBRARY_PATH/"data/schemas/sbom.json").freeze

  # Instantiates a {SBOM} for a new installation of a formula.
  sig { params(formula: Formula, tab: Tab).returns(T.attached_class) }
  def self.create(formula, tab)
    active_spec = if formula.stable?
      T.must(formula.stable)
    else
      T.must(formula.head)
    end
    active_spec_sym = formula.active_spec_sym

    attributes = {
      name:                 formula.name,
      homebrew_version:     HOMEBREW_VERSION,
      spdxfile:             SBOM.spdxfile(formula),
      time:                 tab.time || Time.now,
      source_modified_time: tab.source_modified_time.to_i,
      compiler:             tab.compiler,
      stdlib:               tab.stdlib,
      runtime_dependencies: SBOM.runtime_deps_hash(Array(tab.runtime_dependencies)),
      license:              SPDX.license_expression_to_string(formula.license),
      built_on:             DevelopmentTools.build_system_info,
      source:               {
        path:         formula.specified_path.to_s,
        tap:          formula.tap&.name,
        tap_git_head: nil, # Filled in later if possible
        spec:         active_spec_sym.to_s,
        patches:      active_spec.patches,
        bottle:       formula.bottle_hash,
        active_spec_sym =>       {
          version:  active_spec.version,
          url:      active_spec.url,
          checksum: active_spec.checksum,
        },
      },
    }

    # We can only get `tap_git_head` if the tap is installed locally
    attributes[:source][:tap_git_head] = T.must(formula.tap).git_head if formula.tap&.installed?

    new(attributes)
  end

  sig { params(formula: Formula).returns(Pathname) }
  def self.spdxfile(formula)
    formula.prefix/FILENAME
  end

  sig { params(deps: T::Array[T::Hash[String, String]]).returns(T::Array[T::Hash[String, String]]) }
  def self.runtime_deps_hash(deps)
    deps.map do |dep|
      full_name = dep.fetch("full_name")
      dep_formula = Formula[full_name]
      {
        "full_name"           => full_name,
        "pkg_version"         => dep.fetch("pkg_version"),
        "name"                => dep_formula.name,
        "license"             => SPDX.license_expression_to_string(dep_formula.license),
        "bottle"              => dep_formula.bottle_hash,
        "formula_pkg_version" => dep_formula.pkg_version.to_s,
      }
    end
  end

  sig { params(formula: Formula).returns(T::Boolean) }
  def self.exist?(formula)
    spdxfile(formula).exist?
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def self.schema
    @schema ||= JSON.parse(SCHEMA_FILE.read, freeze: true)
  end

  sig { params(bottling: T::Boolean).returns(T::Array[T::Hash[String, T.untyped]]) }
  def schema_validation_errors(bottling: false)
    unless require? "json_schemer"
      error_message = "Need json_schemer to validate SBOM, run `brew install-bundler-gems --add-groups=bottle`!"
      odie error_message if ENV["HOMEBREW_ENFORCE_SBOM"]
      return []
    end

    schemer = JSONSchemer.schema(SBOM.schema)
    data = to_spdx_sbom(bottling:)

    schemer.validate(data).map { |error| error["error"] }
  end

  sig { params(bottling: T::Boolean).returns(T::Boolean) }
  def valid?(bottling: false)
    validation_errors = schema_validation_errors(bottling:)
    return true if validation_errors.empty?

    opoo "SBOM validation errors:"
    validation_errors.each(&:puts)

    odie "Failed to validate SBOM against JSON schema!" if ENV["HOMEBREW_ENFORCE_SBOM"]

    false
  end

  sig { params(validate: T::Boolean, bottling: T::Boolean).void }
  def write(validate: true, bottling: false)
    # If this is a new installation, the cache of installed formulae
    # will no longer be valid.
    Formula.clear_cache unless spdxfile.exist?

    if validate && !valid?(bottling:)
      opoo "SBOM is not valid, not writing to disk!"
      return
    end

    spdxfile.atomic_write(JSON.pretty_generate(to_spdx_sbom(bottling:)))
  end

  private

  attr_reader :name, :homebrew_version, :time, :stdlib, :source, :built_on, :license
  attr_accessor :spdxfile

  sig { params(attributes: Hash).void }
  def initialize(attributes = {})
    attributes.each { |key, value| instance_variable_set(:"@#{key}", value) }
  end

  sig {
    params(
      runtime_dependency_declaration: T::Array[Hash],
      compiler_declaration:           Hash,
      bottling:                       T::Boolean,
    ).returns(T::Array[Hash])
  }
  def generate_relations_json(runtime_dependency_declaration, compiler_declaration, bottling:)
    runtime = runtime_dependency_declaration.map do |dependency|
      {
        spdxElementId:      dependency[:SPDXID],
        relationshipType:   "RUNTIME_DEPENDENCY_OF",
        relatedSpdxElement: "SPDXRef-Bottle-#{name}",
      }
    end

    patches = source[:patches].each_with_index.map do |_patch, index|
      {
        spdxElementId:      "SPDXRef-Patch-#{name}-#{index}",
        relationshipType:   "PATCH_APPLIED",
        relatedSpdxElement: "SPDXRef-Archive-#{name}-src",
      }
    end

    base = T.let([{
      spdxElementId:      "SPDXRef-File-#{name}",
      relationshipType:   "PACKAGE_OF",
      relatedSpdxElement: "SPDXRef-Archive-#{name}-src",
    }], T::Array[Hash])

    unless bottling
      base << {
        spdxElementId:      "SPDXRef-Compiler",
        relationshipType:   "BUILD_TOOL_OF",
        relatedSpdxElement: "SPDXRef-Package-#{name}-src",
      }

      if compiler_declaration["SPDXRef-Stdlib"].present?
        base << {
          spdxElementId:      "SPDXRef-Stdlib",
          relationshipType:   "DEPENDENCY_OF",
          relatedSpdxElement: "SPDXRef-Bottle-#{name}",
        }
      end
    end

    runtime + patches + base
  end

  sig {
    params(runtime_dependency_declaration: T::Array[Hash],
           compiler_declaration:           Hash,
           bottling:                       T::Boolean).returns(
             T::Array[
              T::Hash[
                Symbol,
                T.any(String, T::Array[T::Hash[Symbol, String]]),
              ],
            ],
           )
  }
  def generate_packages_json(runtime_dependency_declaration, compiler_declaration, bottling:)
    bottle = []
    if !bottling && (bottle_info = get_bottle_info(source[:bottle])) &&
       (stable_version = source.dig(:stable, :version))
      bottle << {
        SPDXID:           "SPDXRef-Bottle-#{name}",
        name:             name.to_s,
        versionInfo:      stable_version.to_s,
        filesAnalyzed:    false,
        licenseDeclared:  assert_value(nil),
        builtDate:        source_modified_time.to_s,
        licenseConcluded: assert_value(license),
        downloadLocation: bottle_info.fetch("url"),
        copyrightText:    assert_value(nil),
        externalRefs:     [
          {
            referenceCategory: "PACKAGE-MANAGER",
            referenceLocator:  "pkg:brew/#{tap}/#{name}@#{stable_version}",
            referenceType:     "purl",
          },
        ],
        checksums:        [
          {
            algorithm:     "SHA256",
            checksumValue: bottle_info.fetch("sha256"),
          },
        ],
      }
    end

    compiler_declarations = if bottling
      []
    else
      compiler_declaration.values
    end

    [
      {
        SPDXID:           "SPDXRef-Archive-#{name}-src",
        name:             name.to_s,
        versionInfo:      spec_version.to_s,
        filesAnalyzed:    false,
        licenseDeclared:  assert_value(nil),
        builtDate:        source_modified_time.to_s,
        licenseConcluded: assert_value(license),
        downloadLocation: source[spec_symbol][:url],
        copyrightText:    assert_value(nil),
        externalRefs:     [],
        checksums:        [
          {
            algorithm:     "SHA256",
            checksumValue: source[spec_symbol][:checksum].to_s,
          },
        ],
      },
    ] + runtime_dependency_declaration + compiler_declarations + bottle
  end

  sig {
    params(bottling: T::Boolean).returns(T::Array[T::Hash[Symbol,
                                                          T.any(T::Boolean, String,
                                                                T::Array[T::Hash[Symbol, String]])]])
  }
  def full_spdx_runtime_dependencies(bottling:)
    return [] if bottling || @runtime_dependencies.blank?

    @runtime_dependencies.compact.filter_map do |dependency|
      next unless dependency.present?

      bottle_info = get_bottle_info(dependency["bottle"])
      next unless bottle_info.present?

      # Only set bottle URL if the dependency is the same version as the formula/bottle.
      bottle_url = bottle_info["url"] if dependency["pkg_version"] == dependency["formula_pkg_version"]

      dependency_json = {
        SPDXID:           "SPDXRef-Package-SPDXRef-#{dependency["name"].tr("/", "-")}-#{dependency["pkg_version"]}",
        name:             dependency["name"],
        versionInfo:      dependency["pkg_version"],
        filesAnalyzed:    false,
        licenseDeclared:  assert_value(nil),
        licenseConcluded: assert_value(dependency["license"]),
        downloadLocation: assert_value(bottle_url),
        copyrightText:    assert_value(nil),
        checksums:        [
          {
            algorithm:     "SHA256",
            checksumValue: assert_value(bottle_info["sha256"]),
          },
        ],
        externalRefs:     [
          {
            referenceCategory: "PACKAGE-MANAGER",
            referenceLocator:  "pkg:brew/#{dependency["full_name"]}@#{dependency["pkg_version"]}",
            referenceType:     "purl",
          },
        ],
      }
      dependency_json
    end
  end

  sig { params(bottling: T::Boolean).returns(T::Hash[Symbol, T.any(String, T::Array[T::Hash[Symbol, String]])]) }
  def to_spdx_sbom(bottling:)
    runtime_full = full_spdx_runtime_dependencies(bottling:)

    compiler_info = {
      "SPDXRef-Compiler" => {
        SPDXID:           "SPDXRef-Compiler",
        name:             compiler.to_s,
        versionInfo:      assert_value(built_on["xcode"]),
        filesAnalyzed:    false,
        licenseDeclared:  assert_value(nil),
        licenseConcluded: assert_value(nil),
        copyrightText:    assert_value(nil),
        downloadLocation: assert_value(nil),
        checksums:        [],
        externalRefs:     [],
      },
    }

    if stdlib.present?
      compiler_info["SPDXRef-Stdlib"] = {
        SPDXID:           "SPDXRef-Stdlib",
        name:             stdlib.to_s,
        versionInfo:      stdlib.to_s,
        filesAnalyzed:    false,
        licenseDeclared:  assert_value(nil),
        licenseConcluded: assert_value(nil),
        copyrightText:    assert_value(nil),
        downloadLocation: assert_value(nil),
        checksums:        [],
        externalRefs:     [],
      }
    end

    # Improve reproducibility when bottling.
    if bottling
      created = source_modified_time.iso8601
      creators = ["Tool: https://github.com/Homebrew/brew"]
    else
      created = Time.at(time).utc.iso8601
      creators = ["Tool: https://github.com/Homebrew/brew@#{homebrew_version}"]
    end

    packages = generate_packages_json(runtime_full, compiler_info, bottling:)
    {
      SPDXID:            "SPDXRef-DOCUMENT",
      spdxVersion:       "SPDX-2.3",
      name:              "SBOM-SPDX-#{name}-#{spec_version}",
      creationInfo:      { created:, creators: },
      dataLicense:       "CC0-1.0",
      documentNamespace: "https://formulae.brew.sh/spdx/#{name}-#{spec_version}.json",
      documentDescribes: packages.map { |dependency| dependency[:SPDXID] },
      files:             [],
      packages:,
      relationships:     generate_relations_json(runtime_full, compiler_info, bottling:),
    }
  end

  sig { params(base: T.nilable(T::Hash[String, Hash])).returns(T.nilable(T::Hash[String, String])) }
  def get_bottle_info(base)
    return unless base.present?

    files = base["files"].presence
    return unless files

    files[Utils::Bottles.tag.to_sym] || files[:all]
  end

  sig { returns(Symbol) }
  def compiler
    @compiler.presence&.to_sym || DevelopmentTools.default_compiler
  end

  sig { returns(T.nilable(Tap)) }
  def tap
    tap_name = source[:tap]
    Tap.fetch(tap_name) if tap_name
  end

  sig { returns(Symbol) }
  def spec_symbol
    source.fetch(:spec).to_sym
  end

  sig { returns(T.nilable(Version)) }
  def spec_version
    source.fetch(spec_symbol)[:version]
  end

  sig { returns(Time) }
  def source_modified_time
    Time.at(@source_modified_time).utc
  end

  sig { params(val: T.untyped).returns(T.any(String, Symbol)) }
  def assert_value(val)
    return :NOASSERTION.to_s unless val.present?

    val
  end
end
