# frozen_string_literal: true

module RBS
  module Annotate
    class RDocAnnotator
      attr_reader :source
      attr_accessor :include_arg_lists, :include_filename

      def initialize(source:)
        @source = source

        @include_arg_lists = true
        @include_filename = true
      end

      def annotate_file(path, preserve:)
        content = path.read()

        decls = Parser.parse_signature(content)

        annotate_decls(decls)

        path.open("w") do |io|
          Writer.new(out: io).preserve!(preserve: preserve).write(decls)
        end
      end

      def annotate_decls(decls, outer: [])
        decls.each do |decl|
          case decl
          when AST::Declarations::Class, AST::Declarations::Module
            annotate_class(decl, outer: outer)
          when AST::Declarations::Constant
            annotate_constant(decl, outer: outer)
          end
        end
      end

      def each_part(subjects, tester:)
        if block_given?
          subjects.each do |subject, docs|
            Formatter.each_part(subject.comment) do |doc|
              if tester.test_path(doc.file || raise)
                yield [doc, subject]
              end
            end
          end
        else
          enum_for :each_part, tester: tester
        end
      end

      def resolve_doc_source(copy, tester:)
        case
        when copy && (mn = copy.method_name) && copy.singleton?
          doc_for_method(copy.type_name, singleton_method: mn, tester: tester)
        when copy && (mn = copy.method_name) && !copy.singleton?
          doc_for_method(copy.type_name, instance_method: mn, tester: tester)
        when copy
          doc_for_class(copy.type_name, tester: tester) || doc_for_constant(copy.type_name, tester: tester)
        else
          yield
        end
      end

      def doc_for_class(name, tester:)
        if clss = source.find_class(name)
          formatter = Formatter.new()

          each_part(clss, tester: tester) do |doc, _|
            text = Formatter.translate(doc) or next

            unless text.empty?
              if include_filename
                formatter << "<!-- rdoc-file=#{doc.file} -->"
              end
              formatter << text

              formatter.margin
            end
          end

          formatter.format(newline_at_end: true)
        end
      end

      def doc_for_constant(name, tester:)
        if constants = source.find_const(name)
          formatter = Formatter.new

          each_part(constants, tester: tester) do |doc, _|
            text = Formatter.translate(doc) or next

            unless text.empty?
              if include_filename
                formatter << "<!-- rdoc-file=#{doc.file} -->"
              end

              formatter << text

              formatter.margin
            end
          end

          formatter.format(newline_at_end: true)
        end
      end

      def doc_for_method0(typename, instance_method: nil, singleton_method: nil, tester:)
        ms = source.find_method(typename, instance_method: instance_method) if instance_method
        ms = source.find_method(typename, singleton_method: singleton_method) if singleton_method

        if ms
          formatter = Formatter.new

          each_part(ms, tester: tester) do |doc, method|
            text = Formatter.translate(doc) or next
            # @type var as: String?
            as = (_ = method).arglists

            if include_arg_lists && as
              formatter << "<!--"
              formatter << "  rdoc-file=#{doc.file}" if include_filename
              as.chomp.split("\n").each do |line|
                formatter << "  - #{line.strip}"
              end
              formatter << "-->"
            else
              if include_filename
                formatter << "<!-- rdoc-file=#{doc.file} -->"
              end
            end

            unless text.empty?
              formatter << text
            end

            formatter.margin(separator: "----")
          end

          formatter.format(newline_at_end: false)
        end
      end

      def doc_for_method(typename, instance_method: nil, singleton_method: nil, tester:)
        formatter = Formatter.new()

        case
        when method = instance_method
          doc = doc_for_alias(typename, name: method, singleton: false, tester: tester)
          doc = doc_for_method0(typename, instance_method: method, tester: tester) if !doc || doc.empty?
          if !doc || doc.empty?
            if (s = method.to_s) =~ /\A[a-zA-Z_]/
              # may be attribute
              doc =
                if s.end_with?("=")
                  doc_for_attribute(typename, s.delete_suffix("=").to_sym, require: "W", singleton: false, tester: tester)
                else
                  doc_for_attribute(typename, s.to_sym, require: "R", singleton: false, tester: tester)
                end
            end
          end
        when method = singleton_method
          doc = doc_for_alias(typename, name: method, singleton: true, tester: tester)
          doc = doc_for_method0(typename, singleton_method: method, tester: tester) if !doc || doc.empty?
          if !doc || doc.empty?
            if (s = method.to_s) =~ /\A[a-zA-Z_]/
              # may be attribute
              doc =
                if s.end_with?("=")
                  doc_for_attribute(typename, s.delete_suffix("=").to_sym, require: "W", singleton: true, tester: tester)
                else
                  doc_for_attribute(typename, s.to_sym, require: "R", singleton: true, tester: tester)
                end
            end
          end
        else
          raise
        end

        if doc
          formatter << doc
          formatter.format(newline_at_end: true)
        end
      end

      def doc_for_alias(typename, name:, singleton:, tester:)
        if as =
          if singleton
            source.find_method(typename, singleton_method: name)
          else
            source.find_method(typename, instance_method: name)
          end

          formatter = Formatter.new

          each_part(as, tester: tester) do |doc, obj|
            # @type var method: RDoc::AnyMethod
            method = _ = obj

            if method.is_alias_for
              text = Formatter.translate(doc) or next

              unless text.empty?
                formatter << "<!-- rdoc-file=#{doc.file} -->" if include_filename
                formatter << text
              end
            end
          end

          formatter.format(newline_at_end: true)
        end
      end

      def doc_for_attribute(typename, attr_name, require: nil, singleton:, tester:)
        if as = source.find_attribute(typename, attr_name, singleton: singleton)
          as = as.select do |attr|
            case require
            when "R"
              attr.rw == "R" || attr.rw == "RW"
            when "W"
              attr.rw == "W" || attr.rw == "RW"
            else
              true
            end
          end

          return if as.empty?

          formatter = Formatter.new()

          each_part(as, tester: tester) do |doc, obj|
            if text = Formatter.translate(doc)
              unless text.empty?
                formatter << "<!-- rdoc-file=#{doc.file} -->" if include_filename
                formatter << text
              end
            end
          end

          formatter.format(newline_at_end: true)
        end
      end

      def annotate_class(decl, outer:)
        annots = annotations(decl)

        full_name = resolve_name(decl.name, outer: outer)
        unless annots.skip?
          text = resolve_doc_source(annots.copy_annotation, tester: annots) { doc_for_class(full_name, tester: annots) }
        end

        replace_comment(decl, text)

        unless annots.skip_all?
          outer_ = outer + [decl.name.to_namespace]

          decl.each_member do |member|
            case member
            when AST::Members::MethodDefinition
              annotate_method(full_name, member)
            when AST::Members::Alias
              annotate_alias(full_name, member)
            when AST::Members::AttrReader, AST::Members::AttrAccessor, AST::Members::AttrWriter
              annotate_attribute(full_name, member)
            end
          end

          annotate_decls(decl.each_decl.to_a, outer: outer_)
        end
      end

      def annotate_constant(const, outer:)
        annots = Annotations.new([])

        full_name = resolve_name(const.name, outer: outer)
        text = doc_for_constant(full_name, tester: annots)

        replace_comment(const, text)
      end

      def annotate_alias(typename, als)
        annots = annotations(als)

        unless annots.skip?
          text = resolve_doc_source(annots.copy_annotation, tester: annots) do
            case als.kind
            when :instance
              doc_for_method(typename, instance_method: als.new_name, tester: annots)
            when :singleton
              doc_for_method(typename, singleton_method: als.new_name, tester: annots)
            end
          end
        end

        replace_comment(als, text)
      end

      def join_docs(docs, separator: "----")
        formatter = Formatter.new()

        docs.each do |doc|
          formatter << doc
          formatter.margin(separator: separator)
        end

        unless formatter.empty?
          formatter.format(newline_at_end: true)
        end
      end

      def annotate_method(typename, method)
        annots = annotations(method)

        unless annots.skip?
          text = resolve_doc_source(annots.copy_annotation, tester: annots) {
            case method.kind
            when :singleton
              doc_for_method(typename, singleton_method: method.name, tester: annots)
            when :instance
              if method.name == :initialize
                doc_for_method(typename, instance_method: :initialize, tester: annots) ||
                  doc_for_method(typename, singleton_method: :new, tester: annots)
              else
                doc_for_method(typename, instance_method: method.name, tester: annots)
              end
            when :singleton_instance
              join_docs(
                [
                  doc_for_method(typename, singleton_method: method.name, tester: annots),
                  doc_for_method(typename, instance_method: method.name, tester: annots)
                ].uniq
              )
            end
          }
        end

        replace_comment(method, text)
      end

      def annotate_attribute(typename, attr)
        annots = annotations(attr)

        unless annots.skip?
          text = resolve_doc_source(annots.copy_annotation, tester: annots) do
            # @type var docs: Array[String?]
            docs = []

            case attr.kind
            when :instance
              if attr.is_a?(AST::Members::AttrReader) || attr.is_a?(AST::Members::AttrAccessor)
                docs << doc_for_method(typename, instance_method: attr.name, tester: annots)
              end
              if attr.is_a?(AST::Members::AttrWriter) || attr.is_a?(AST::Members::AttrAccessor)
                docs << doc_for_method(typename, instance_method: :"#{attr.name}=", tester: annots)
              end
            when :singleton
              if attr.is_a?(AST::Members::AttrReader) || attr.is_a?(AST::Members::AttrAccessor)
                docs << doc_for_method(typename, singleton_method: attr.name, tester: annots)
              end
              if attr.is_a?(AST::Members::AttrWriter) || attr.is_a?(AST::Members::AttrAccessor)
                docs << doc_for_method(typename, singleton_method: :"#{attr.name}=", tester: annots)
              end
            end
            join_docs(docs.uniq)
          end
        end

        replace_comment(attr, text)
      end

      def replace_comment(commented, string)
        if string
          if string.empty?
            commented.instance_variable_set(:@comment, nil)
          else
            commented.instance_variable_set(
              :@comment,
              AST::Comment.new(location: nil, string: string)
            )
          end
        end
      end

      def resolve_name(name, outer:)
        namespace = outer.inject(RBS::Namespace.root) do |ns1, ns2|
          ns1 + ns2
        end

        name.with_prefix(namespace).relative!
      end

      def annotations(annots)
        # @type var as: Array[Annotations::t]
        as = _ = annots.annotations.map {|annot| Annotations.parse(annot) }.compact
        Annotations.new(as)
      end
    end
  end
end
