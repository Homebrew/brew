# typed: strict
# frozen_string_literal: true

require "json"
require "development_tools"
require "utils/curl"
require "utils/output"

# Rather than calling `new` directly, use one of the class methods like {SBOM.create}.
class SBOM
  include Utils::Output::Mixin

  FILENAME = "sbom.spdx.json"
  SCHEMA_FILE = T.let((HOMEBREW_LIBRARY_PATH/"data/schemas/sbom.json").freeze, Pathname)
  SPDXHash = T.type_alias { T::Hash[String, Object] }
  SPDXSymbolHash = T.type_alias { T::Hash[Symbol, Object] }

  class Source < T::Struct
    const :path, String
    const :tap_name, T.nilable(String)
    const :tap_git_head, T.nilable(String)
    const :spec, Symbol
    const :patches, T::Array[T.any(EmbeddedPatch, ExternalPatch)]
    const :bottle, T::Hash[String, Object]
    const :version, T.nilable(Version)
    const :url, T.nilable(String)
    const :checksum, T.nilable(Checksum)
  end

  # Instantiates a {SBOM} for a new installation of a formula.
  sig { params(formula: Formula, tab: Tab).returns(T.attached_class) }
  def self.create(formula, tab)
    active_spec = if formula.stable?
      T.must(formula.stable)
    else
      T.must(formula.head)
    end
    active_spec_sym = formula.active_spec_sym

    new(
      name:                 formula.name,
      spdxfile:             SBOM.spdxfile(formula),
      source_modified_time: tab.source_modified_time.to_i,
      compiler:             tab.compiler,
      stdlib:               tab.stdlib,
      runtime_dependencies: SBOM.runtime_deps_hash(T.cast(Array(tab.runtime_dependencies),
                                                          T::Array[T::Hash[String, Object]])),
      license:              SPDX.license_expression_to_string(formula.license),
      built_on:             DevelopmentTools.build_system_info,
      source:               Source.new(
        path:         formula.specified_path.to_s,
        tap_name:     formula.tap&.name,
        # We can only get `tap_git_head` if the tap is installed locally
        tap_git_head: (formula.tap!.git_head if formula.tap&.installed?),
        spec:         active_spec_sym,
        patches:      active_spec.patches,
        bottle:       formula.bottle_hash,
        version:      active_spec.version,
        url:          active_spec.url,
        checksum:     active_spec.checksum,
      ),
    )
  end

  sig { params(formula: Formula).returns(Pathname) }
  def self.spdxfile(formula)
    formula.prefix/FILENAME
  end

  sig { params(deps: T::Array[T::Hash[String, Object]]).returns(T::Array[T::Hash[String, Object]]) }
  def self.runtime_deps_hash(deps)
    deps.map do |dep|
      full_name = dep.fetch("full_name").to_s
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

  sig {
    params(
      supplement:        T.nilable(SPDXHash),
      formula_full_name: String,
      formula_name:      String,
      version:           Version,
      tar_gz_sha256:     String,
      root_url:          String,
      license:           String,
      created_date:      String,
    ).returns(T.nilable(String))
  }
  def self.github_packages_sbom_supplement_annotation(supplement, formula_full_name:, formula_name:, version:,
                                                      tar_gz_sha256:, root_url:, license:, created_date:)
    require "github_packages"

    add_bottle_package_to_supplement(
      supplement,
      bottle_package(
        formula_full_name,
        formula_name,
        version,
        tar_gz_sha256,
        root_url:,
        license:,
        created_date:,
      ),
    )&.to_json
  end

  sig {
    params(
      formula_full_name: String,
      formula_name:      String,
      version:           Version,
      tar_gz_sha256:     String,
      root_url:          String,
      license:           String,
      created_date:      String,
    ).returns(SPDXHash)
  }
  def self.bottle_package(formula_full_name, formula_name, version, tar_gz_sha256, root_url:, license:, created_date:)
    {
      "SPDXID"           => "SPDXRef-Bottle-#{formula_name}",
      "name"             => formula_name,
      "versionInfo"      => version.to_s,
      "filesAnalyzed"    => false,
      "licenseDeclared"  => "NOASSERTION",
      "builtDate"        => created_date,
      "licenseConcluded" => license.presence || "NOASSERTION",
      "downloadLocation" => "#{root_url}/#{GitHubPackages.image_formula_name(formula_name)}/" \
                            "blobs/sha256:#{tar_gz_sha256}",
      "copyrightText"    => "NOASSERTION",
      "externalRefs"     => [
        {
          "referenceCategory" => "PACKAGE-MANAGER",
          "referenceLocator"  => "pkg:brew/#{formula_full_name}@#{version}",
          "referenceType"     => "purl",
        },
      ],
      "checksums"        => [
        {
          "algorithm"     => "SHA256",
          "checksumValue" => tar_gz_sha256,
        },
      ],
    }
  end
  private_class_method :bottle_package

  sig {
    params(
      spdxfile:         Pathname,
      homebrew_version: String,
      time:             Integer,
      supplement:       T.nilable(SPDXHash),
    ).void
  }
  def self.update_pour_metadata(spdxfile, homebrew_version:, time:, supplement: nil)
    return unless spdxfile.exist?

    spdx = JSON.parse(spdxfile.read)
    return unless spdx.is_a?(Hash)

    creation_info = spdx["creationInfo"]
    return unless creation_info.is_a?(Hash)

    creation_info["created"] = Time.at(time).utc.iso8601
    creation_info["creators"] = ["Tool: https://github.com/Homebrew/brew@#{homebrew_version}"]
    merge_spdx_supplement(spdx, supplement) if supplement
    spdxfile.atomic_write(JSON.pretty_generate(spdx))
  rescue JSON::ParserError
    nil
  end

  sig { returns(T::Hash[String, T.anything]) }
  def self.schema
    @schema ||= T.let(JSON.parse(SCHEMA_FILE.read, freeze: true), T.nilable(T::Hash[String, Object]))
  end

  sig { params(data: T.nilable(T::Hash[Symbol, T.anything]), bottling: T::Boolean).returns(T::Array[String]) }
  def schema_validation_errors(data = nil, bottling: false)
    unless Homebrew.require? "json_schemer"
      error_message = "Need json_schemer to validate SBOM, run `brew install-bundler-gems --add-groups=bottle`!"
      odie error_message if ENV["HOMEBREW_ENFORCE_SBOM"]
      return []
    end

    schemer = JSONSchemer.schema(SBOM.schema)

    schemer.validate(data || to_spdx_sbom(bottling:)).map { |error| error["error"] }
  end

  sig { params(data: T.nilable(T::Hash[Symbol, T.anything]), bottling: T::Boolean).returns(T::Boolean) }
  def valid?(data = nil, bottling: false)
    validation_errors = schema_validation_errors(data, bottling:)
    return true if validation_errors.empty?

    opoo "SBOM validation errors:"
    validation_errors.each { |error| $stderr.puts error }

    odie "Failed to validate SBOM against JSON schema!" if ENV["HOMEBREW_ENFORCE_SBOM"]

    false
  end

  sig { params(validate: T::Boolean, bottling: T::Boolean).void }
  def write(validate: true, bottling: false)
    # If this is a new installation, the cache of installed formulae
    # will no longer be valid.
    Formula.clear_cache unless spdxfile.exist?

    spdx_sbom = to_spdx_sbom(bottling:)

    if validate && !valid?(spdx_sbom, bottling:)
      opoo "SBOM is not valid, not writing to disk!"
      return
    end

    spdxfile.atomic_write(JSON.pretty_generate(spdx_sbom))
  end

  sig { params(bottling: T::Boolean).returns(T::Hash[Symbol, T.anything]) }
  def to_spdx_sbom(bottling: false)
    runtime_full = full_spdx_runtime_dependencies(bottling:)
    compiler_info = compiler_packages
    compiler_info = {} if bottling

    packages = generate_packages_json(runtime_full, compiler_info, bottling:)
    files = generate_files_json
    {
      SPDXID:            "SPDXRef-DOCUMENT",
      spdxVersion:       "SPDX-2.3",
      name:              "SBOM-SPDX-#{name}-#{spec_version}",
      creationInfo:      {
        created:  source_modified_time.iso8601,
        creators: ["Tool: https://github.com/Homebrew/brew"],
      },
      dataLicense:       "CC0-1.0",
      documentNamespace: "https://formulae.brew.sh/spdx/#{name}-#{spec_version}.json",
      documentDescribes: packages.map { |dependency| dependency[:SPDXID] },
      files:,
      packages:,
      relationships:     generate_relations_json(runtime_full, compiler_info, bottling:),
    }
  end

  sig { returns(SPDXHash) }
  def to_spdx_supplement
    runtime_full = full_spdx_runtime_dependencies(bottling: false)
    compiler_info = compiler_packages
    packages = runtime_full + compiler_info.values
    relationships = T.let([], T::Array[SPDXSymbolHash])
    runtime_full.each do |dependency|
      relationships << {
        spdxElementId:      dependency[:SPDXID],
        relationshipType:   "RUNTIME_DEPENDENCY_OF",
        relatedSpdxElement: bottle_spdx_id,
      }
    end

    if compiler_info["SPDXRef-Compiler"].present?
      relationships << {
        spdxElementId:      "SPDXRef-Compiler",
        relationshipType:   "BUILD_TOOL_OF",
        relatedSpdxElement: "SPDXRef-Archive-#{name}-src",
      }
    end

    if compiler_info["SPDXRef-Stdlib"].present?
      relationships << {
        spdxElementId:      "SPDXRef-Stdlib",
        relationshipType:   "DEPENDENCY_OF",
        relatedSpdxElement: bottle_spdx_id,
      }
    end

    {
      "documentDescribes" => packages.map { |package| package[:SPDXID] },
      "packages"          => packages,
      "relationships"     => relationships,
    }
  end

  private

  sig { params(spdx: SPDXHash, supplement: SPDXHash).void }
  def self.merge_spdx_supplement(spdx, supplement)
    ["documentDescribes", "packages", "relationships"].each do |key|
      spdx_value = spdx[key]
      supplement_value = supplement[key]
      next if !spdx_value.is_a?(Array) || !supplement_value.is_a?(Array)

      spdx_value.concat(supplement_value)
    end
  end
  private_class_method :merge_spdx_supplement

  sig {
    params(
      supplement:     T.nilable(SPDXHash),
      bottle_package: SPDXHash,
    ).returns(T.nilable(SPDXHash))
  }
  def self.add_bottle_package_to_supplement(supplement, bottle_package)
    return if supplement.nil?

    if (tags = supplement["tags"]).is_a?(Hash)
      tag_supplements = tags.filter_map do |tag, tag_supplement|
        next if !tag.is_a?(String) || !tag_supplement.is_a?(Hash)

        [tag, add_bottle_package_to_supplement(tag_supplement, bottle_package)]
      end.to_h.compact
      return { "tags" => tag_supplements } if tag_supplements.present?
    end

    packages = supplement["packages"]
    return unless packages.is_a?(Array)

    document_describes = supplement["documentDescribes"]
    relationships = supplement["relationships"]
    document_describes += [bottle_package.fetch("SPDXID")] if document_describes.is_a?(Array)
    {
      "documentDescribes" => document_describes.is_a?(Array) ? document_describes : [],
      "packages"          => packages + [bottle_package],
      "relationships"     => relationships.is_a?(Array) ? relationships : [],
    }
  end
  private_class_method :add_bottle_package_to_supplement

  sig { returns(String) }
  attr_reader :name

  sig { returns(T.nilable(T.any(String, Symbol))) }
  attr_reader :stdlib

  sig { returns(Source) }
  attr_reader :source

  sig { returns(T::Hash[String, T.nilable(String)]) }
  attr_reader :built_on

  sig { returns(T.nilable(String)) }
  attr_reader :license

  sig { returns(Pathname) }
  attr_accessor :spdxfile

  sig {
    params(
      name:                 String,
      spdxfile:             Pathname,
      source_modified_time: Integer,
      compiler:             T.any(String, Symbol),
      stdlib:               T.nilable(T.any(String, Symbol)),
      runtime_dependencies: T::Array[T::Hash[String, Object]],
      license:              T.nilable(String),
      built_on:             T::Hash[String, T.nilable(String)],
      source:               Source,
    ).void
  }
  def initialize(name:, spdxfile:, source_modified_time:, compiler:, stdlib:, runtime_dependencies:,
                 license:, built_on:, source:)
    @name = name
    @spdxfile = spdxfile
    @source_modified_time = source_modified_time
    @compiler = compiler
    @stdlib = stdlib
    @runtime_dependencies = runtime_dependencies
    @license = license
    @built_on = built_on
    @source = source
  end

  sig { returns(T::Hash[String, SPDXSymbolHash]) }
  def compiler_packages
    packages = {
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
      packages["SPDXRef-Stdlib"] = {
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

    packages
  end

  sig {
    params(
      runtime_dependency_declaration: T::Array[SPDXSymbolHash],
      compiler_declaration:           T::Hash[String, Object],
      bottling:                       T::Boolean,
    ).returns(T::Array[SPDXSymbolHash])
  }
  def generate_relations_json(runtime_dependency_declaration, compiler_declaration, bottling:)
    runtime = runtime_dependency_declaration.map do |dependency|
      {
        spdxElementId:      dependency[:SPDXID],
        relationshipType:   "RUNTIME_DEPENDENCY_OF",
        relatedSpdxElement: described_package_spdx_id(bottling:),
      }
    end

    patches = source.patches.each_with_index.filter_map do |patch, index|
      next unless patch.is_a?(ExternalPatch)

      {
        spdxElementId:      "SPDXRef-Patch-#{name}-#{index}",
        relationshipType:   "PATCH_APPLIED",
        relatedSpdxElement: "SPDXRef-Archive-#{name}-src",
      }
    end

    base = T.let([], T::Array[SPDXSymbolHash])

    if source.checksum.present?
      base << {
        spdxElementId:      "SPDXRef-File-#{name}",
        relationshipType:   "PACKAGE_OF",
        relatedSpdxElement: "SPDXRef-Archive-#{name}-src",
      }
    end

    unless bottling
      base << {
        spdxElementId:      "SPDXRef-Compiler",
        relationshipType:   "BUILD_TOOL_OF",
        relatedSpdxElement: "SPDXRef-Archive-#{name}-src",
      }

      if compiler_declaration["SPDXRef-Stdlib"].present?
        base << {
          spdxElementId:      "SPDXRef-Stdlib",
          relationshipType:   "DEPENDENCY_OF",
          relatedSpdxElement: described_package_spdx_id(bottling:),
        }
      end
    end

    runtime + patches + base
  end

  sig {
    params(
      runtime_dependency_declaration: T::Array[SPDXSymbolHash],
      compiler_declaration:           T::Hash[String, SPDXSymbolHash],
      bottling:                       T::Boolean,
    ).returns(T::Array[SPDXSymbolHash])
  }
  def generate_packages_json(runtime_dependency_declaration, compiler_declaration, bottling:)
    bottle = []
    if bottle_package?(bottling:) &&
       (bottle_info = get_bottle_info(source.bottle)) &&
       (stable_version = source.version)
      bottle << {
        SPDXID:           "SPDXRef-Bottle-#{name}",
        name:             name.to_s,
        versionInfo:      stable_version.to_s,
        filesAnalyzed:    false,
        licenseDeclared:  assert_value(nil),
        builtDate:        source_modified_time.iso8601,
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

    patches = source.patches.each_with_index.filter_map do |patch, index|
      next unless patch.is_a?(ExternalPatch)

      package = {
        SPDXID:           "SPDXRef-Patch-#{name}-#{index}",
        name:             "#{name} patch #{index}",
        filesAnalyzed:    false,
        licenseDeclared:  assert_value(nil),
        licenseConcluded: assert_value(nil),
        downloadLocation: assert_value(patch.url),
        copyrightText:    assert_value(nil),
        checksums:        [],
        externalRefs:     [],
      }
      if (checksum = patch.resource.checksum)
        package[:checksums] = [
          {
            algorithm:     "SHA256",
            checksumValue: checksum.hexdigest,
          },
        ]
      end
      package
    end

    [
      {
        SPDXID:           "SPDXRef-Archive-#{name}-src",
        name:             name.to_s,
        versionInfo:      spec_version.to_s,
        filesAnalyzed:    false,
        licenseDeclared:  assert_value(nil),
        builtDate:        source_modified_time.iso8601,
        licenseConcluded: assert_value(license),
        downloadLocation: source.url,
        copyrightText:    assert_value(nil),
        externalRefs:     [],
        checksums:        [
          {
            algorithm:     "SHA256",
            checksumValue: source.checksum.to_s,
          },
        ],
      },
    ] + patches + runtime_dependency_declaration + compiler_declaration.values + bottle
  end

  sig { returns(T::Array[SPDXSymbolHash]) }
  def generate_files_json
    checksum = source.checksum
    return [] unless checksum

    [
      {
        SPDXID:    "SPDXRef-File-#{name}",
        fileName:  source.url.to_s.split("/").last.presence || "#{name}-#{spec_version}",
        checksums: [
          {
            algorithm:     "SHA256",
            checksumValue: checksum.hexdigest,
          },
        ],
      },
    ]
  end

  sig {
    params(bottling: T::Boolean).returns(T::Array[SPDXSymbolHash])
  }
  def full_spdx_runtime_dependencies(bottling:)
    return [] if bottling || @runtime_dependencies.blank?

    @runtime_dependencies.compact.filter_map do |dependency|
      next unless dependency.present?

      dependency_bottle = dependency["bottle"]
      next unless dependency_bottle.is_a?(Hash)

      bottle_info = get_bottle_info(dependency_bottle)
      next unless bottle_info.present?

      dependency_name = dependency.fetch("name").to_s
      dependency_pkg_version = dependency.fetch("pkg_version").to_s
      dependency_formula_pkg_version = dependency.fetch("formula_pkg_version").to_s

      # Only set bottle URL if the dependency is the same version as the formula/bottle.
      bottle_url = bottle_info["url"] if dependency_pkg_version == dependency_formula_pkg_version

      dependency_json = {
        SPDXID:           "SPDXRef-Package-SPDXRef-#{dependency_name.tr("/", "-")}-#{dependency_pkg_version}",
        name:             dependency_name,
        versionInfo:      dependency_pkg_version,
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
            referenceLocator:  "pkg:brew/#{dependency["full_name"]}@#{dependency_pkg_version}",
            referenceType:     "purl",
          },
        ],
      }
      dependency_json
    end
  end

  sig { params(base: T.nilable(T::Hash[String, Object])).returns(T.nilable(T::Hash[String, String])) }
  def get_bottle_info(base)
    return unless base.present?

    files = base["files"]
    return unless files.is_a?(Hash)

    bottle_info = files[Utils::Bottles.tag.to_sym] || files[:all]
    return unless bottle_info.is_a?(Hash)

    bottle_info.to_h { |key, value| [key.to_s, value.to_s] }
  end

  sig { params(bottling: T::Boolean).returns(T::Boolean) }
  def bottle_package?(bottling:)
    !bottling && get_bottle_info(source.bottle).present? && spec_symbol == :stable && source.version.present?
  end

  sig { params(bottling: T::Boolean).returns(String) }
  def described_package_spdx_id(bottling:)
    if bottle_package?(bottling:)
      bottle_spdx_id
    else
      "SPDXRef-Archive-#{name}-src"
    end
  end

  sig { returns(String) }
  def bottle_spdx_id
    "SPDXRef-Bottle-#{name}"
  end

  sig { returns(Symbol) }
  def compiler
    @compiler.presence&.to_sym || DevelopmentTools.default_compiler
  end

  sig { returns(T.nilable(Tap)) }
  def tap
    tap_name = source.tap_name
    Tap.fetch(tap_name) if tap_name
  end

  sig { returns(Symbol) }
  def spec_symbol
    source.spec
  end

  sig { returns(T.nilable(Version)) }
  def spec_version
    source.version
  end

  sig { returns(Time) }
  def source_modified_time
    Time.at(@source_modified_time).utc
  end

  sig { params(val: Object).returns(String) }
  def assert_value(val)
    return :NOASSERTION.to_s unless val.present?

    val.to_s
  end
end
