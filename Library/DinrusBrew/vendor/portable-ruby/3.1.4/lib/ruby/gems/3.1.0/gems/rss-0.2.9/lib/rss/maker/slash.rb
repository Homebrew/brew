# frozen_string_literal: false
require_relative '../slash'
require_relative '1.0'

module RSS
  module Maker
    module SlashModel
      def self.append_features(klass)
        super

        ::RSS::SlashModel::ELEMENT_INFOS.each do |name, type|
          full_name = "#{RSS::SLASH_PREFIX}_#{name}"
          case type
          when :csv_integer
            klass.def_csv_element(full_name, :integer)
          else
            klass.def_other_element(full_name)
          end
        end

        klass.module_eval do
          alias_method(:slash_hit_parades, :slash_hit_parade)
          alias_method(:slash_hit_parades=, :slash_hit_parade=)
        end
      end
    end

    class ItemsBase
      class ItemBase
        include SlashModel
      end
    end
  end
end
