# frozen_string_literal: true

module RBS
  module Annotate
    class RDocSource
      attr_accessor :with_system_dir, :with_gems_dir, :with_site_dir, :with_home_dir

      attr_reader :extra_dirs

      attr_reader :stores

      def initialize
        self.with_system_dir = true
        self.with_gems_dir = false
        self.with_site_dir = false
        self.with_home_dir = false

        @extra_dirs = []
        @stores = []
      end

      def load
        @stores.clear()

        RDoc::RI::Paths.each(with_system_dir, with_site_dir, with_home_dir, with_gems_dir ? :latest : false, *extra_dirs.map(&:to_s)) do |path, type|
          store = RDoc::Store.new(path, type)
          store.load_all

          @stores << store
        end
      end

      def find_class(typename)
        classes = []

        @stores.each do |store|
          if klass = store.find_class_or_module(typename.relative!.to_s)
            classes << klass
          end
        end

        unless classes.empty?
          classes
        end
      end

      def docs
        if ds = yield
          unless ds.empty?
            ds.map(&:comment)
          end
        end
      end

      def class_docs(typename)
        if classes = find_class(typename)
          classes.map {|klass| klass.comment }
        end
      end

      def find_const(const_name)
        namespace =
          if const_name.namespace.empty?
            TypeName("::Object")
          else
            const_name.namespace.to_type_name
          end

        if classes = find_class(namespace)
          # @type var consts: Array[RDoc::Constant]
          consts = []

          classes.each do |klass|
            if const = klass.constants.find {|c| c.name == const_name.name.to_s }
              consts << const
            end
          end

          unless consts.empty?
            consts
          end
        end
      end

      def find_method(typename, instance_method: nil, singleton_method: nil)
        if classes = find_class(typename)
          # @type var methods: Array[RDoc::AnyMethod]
          methods = []

          classes.each do |klass|
            klass.method_list.each do |method|
              if instance_method && !method.singleton && method.name == instance_method.to_s
                methods << method
              end

              if singleton_method && method.singleton && method.name == singleton_method.to_s
                methods << method
              end
            end
          end

          unless methods.empty?
            methods
          end
        end
      end

      def find_attribute(typename, name, singleton:)
        if klasss = find_class(typename)
          # @type var attrs: Array[RDoc::Attr]
          attrs = []

          klasss.each do |kls|
            attrs.concat(kls.attributes.select {|attr| attr.singleton == singleton && attr.name == name.to_s })
          end

          attrs unless attrs.empty?
        end
      end
    end
  end
end
