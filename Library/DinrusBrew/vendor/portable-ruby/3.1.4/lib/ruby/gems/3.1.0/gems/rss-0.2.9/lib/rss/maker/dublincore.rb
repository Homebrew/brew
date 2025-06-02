# frozen_string_literal: false
require_relative '../dublincore'
require_relative '1.0'

module RSS
  module Maker
    module DublinCoreModel
      def self.append_features(klass)
        super

        ::RSS::DublinCoreModel::ELEMENT_NAME_INFOS.each do |name, plural_name|
          plural_name ||= "#{name}s"
          full_name = "#{RSS::DC_PREFIX}_#{name}"
          full_plural_name = "#{RSS::DC_PREFIX}_#{plural_name}"
          plural_klass_name = "DublinCore#{Utils.to_class_name(plural_name)}"
          klass.def_classed_elements(full_name, "value", plural_klass_name,
                                     full_plural_name, name)
          klass.module_eval(<<-EOC, __FILE__, __LINE__ + 1)
            def new_#{full_name}(value=nil)
              _#{full_name} = #{full_plural_name}.new_#{name}
              _#{full_name}.value = value
              if block_given?
                yield _#{full_name}
              else
                _#{full_name}
              end
            end
          EOC
        end

        klass.module_eval(<<-EOC, __FILE__, __LINE__ + 1)
          # For backward compatibility
          alias #{DC_PREFIX}_rightses #{DC_PREFIX}_rights_list
        EOC
      end

      ::RSS::DublinCoreModel::ELEMENT_NAME_INFOS.each do |name, plural_name|
        plural_name ||= "#{name}s"
        full_name ||= "#{DC_PREFIX}_#{name}"
        full_plural_name ||= "#{DC_PREFIX}_#{plural_name}"
        klass_name = Utils.to_class_name(name)
        full_klass_name = "DublinCore#{klass_name}"
        plural_klass_name = "DublinCore#{Utils.to_class_name(plural_name)}"
        module_eval(<<-EOC, __FILE__, __LINE__ + 1)
        class #{plural_klass_name}Base < Base
          def_array_element(#{name.dump}, #{full_plural_name.dump},
                            #{full_klass_name.dump})

          class #{full_klass_name}Base < Base
            attr_accessor :value
            add_need_initialize_variable("value")
            alias_method(:content, :value)
            alias_method(:content=, :value=)

            def have_required_values?
              @value
            end

            def to_feed(feed, current)
              if value and current.respond_to?(:#{full_name})
                new_item = current.class::#{full_klass_name}.new(value)
                current.#{full_plural_name} << new_item
              end
            end
          end
          #{klass_name}Base = #{full_klass_name}Base
        end
        EOC
      end

      def self.install_dublin_core(klass)
        ::RSS::DublinCoreModel::ELEMENT_NAME_INFOS.each do |name, plural_name|
          plural_name ||= "#{name}s"
          klass_name = Utils.to_class_name(name)
          full_klass_name = "DublinCore#{klass_name}"
          plural_klass_name = "DublinCore#{Utils.to_class_name(plural_name)}"
          klass.module_eval(<<-EOC, __FILE__, __LINE__ + 1)
          class #{plural_klass_name} < #{plural_klass_name}Base
            class #{full_klass_name} < #{full_klass_name}Base
            end
            #{klass_name} = #{full_klass_name}
          end
EOC
        end
      end
    end

    class ChannelBase
      include DublinCoreModel
    end

    class ImageBase; include DublinCoreModel; end
    class ItemsBase
      class ItemBase
        include DublinCoreModel
      end
    end
    class TextinputBase; include DublinCoreModel; end

    makers.each do |maker|
      maker.module_eval(<<-EOC, __FILE__, __LINE__ + 1)
        class Channel
          DublinCoreModel.install_dublin_core(self)
        end

        class Image
          DublinCoreModel.install_dublin_core(self)
        end

        class Items
          class Item
            DublinCoreModel.install_dublin_core(self)
          end
        end

        class Textinput
          DublinCoreModel.install_dublin_core(self)
        end
      EOC
    end
  end
end
