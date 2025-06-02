# frozen_string_literal: true

module RBS
  class Vendorer
    attr_reader :vendor_dir
    attr_reader :loader

    def initialize(vendor_dir:, loader:)
      @vendor_dir = vendor_dir
      @loader = loader
    end

    def ensure_dir
      unless vendor_dir.directory?
        vendor_dir.mkpath
      end

      yield
    end

    def clean!
      ensure_dir do
        RBS.logger.info "Cleaning vendor root: #{vendor_dir}..."
        vendor_dir.rmtree
      end
    end

    def copy!
      # @type var paths: Set[[Pathname, Pathname]]
      paths = Set[]

      if core_root = loader.core_root
        RBS.logger.info "Vendoring core RBSs in #{vendor_dir + "core"}..."
        loader.each_file(core_root, immediate: false, skip_hidden: true) do |file_path|
          paths << [file_path, Pathname("core") + file_path.relative_path_from(core_root)]
        end
      end

      loader.libs.each do |lib|
        case
        when (spec, path = EnvironmentLoader.gem_sig_path(lib.name, lib.version))
          dest_dir = Pathname("#{lib.name}-#{spec.version}")

          RBS.logger.info "Vendoring #{lib.name}(#{spec.version}) RBSs in #{vendor_dir + dest_dir}..."

          loader.each_file(path, skip_hidden: true, immediate: false) do |file_path|
            paths << [file_path, dest_dir + file_path.relative_path_from(path)]
          end

        when (rbs, path = loader.repository.lookup_path(lib.name, lib.version))
          dest_dir = Pathname("#{rbs.name}-#{path.version}")

          RBS.logger.info "Vendoring #{lib.name}(#{path.version}) RBSs in #{vendor_dir + dest_dir}..."

          loader.each_file(path.path, skip_hidden: true, immediate: false) do |file_path|
            paths << [file_path, dest_dir + file_path.relative_path_from(path.path)]
          end
        else
          RBS.logger.error "Couldn't find RBSs for #{lib.name} (#{lib.version}); skipping..."
        end
      end

      paths.each do |from, to|
        dest = vendor_dir + to
        dest.parent.mkpath unless dest.parent.directory?

        FileUtils.copy_file(from.to_s, dest.to_s)
      end
    end
  end
end
