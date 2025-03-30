# typed: strict

module Homebrew
  module Bootsnap
    sig { returns(String) }
    def self.key; end

    sig { returns(String) }
    private_class_method def self.cache_dir; end

    sig { returns(T::Array[String]) }
    private_class_method def self.ignore_directories; end

    sig { returns(T::Boolean) }
    private_class_method def self.enabled?; end

    sig { params(compile_cache: T::Boolean).void }
    def self.load!(compile_cache: true); end

    sig { void }
    def self.reset!; end
  end
end

module Bootsnap
  sig {
    params(
      cache_dir:          String,
      development_mode:   T::Boolean,
      load_path_cache:    T::Boolean,
      ignore_directories: T.nilable(T::Array[String]),
      readonly:           T::Boolean,
      revalidation:       T::Boolean,
      compile_cache_iseq: T::Boolean,
      compile_cache_yaml: T::Boolean,
      compile_cache_json: T::Boolean,
    ).void
  }
  def self.setup(
    cache_dir:,
    development_mode: true,
    load_path_cache: true,
    ignore_directories: nil,
    readonly: false,
    revalidation: false,
    compile_cache_iseq: true,
    compile_cache_yaml: true,
    compile_cache_json: true
  )
  end

  sig { void }
  def self.unload_cache!; end
end
