# frozen_string_literal: true
#--
# = Ruby-space definitions to add DER (de)serialization to classes
#
# = Info
# 'OpenSSL for Ruby 2' project
# Copyright (C) 2002  Michal Rokos <m.rokos@sh.cvut.cz>
# All rights reserved.
#
# = Licence
# This program is licensed under the same licence as Ruby.
# (See the file 'LICENCE'.)
#++
module OpenSSL
  module Marshal
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def _load(string)
        new(string)
      end
    end

    def _dump(_level)
      to_der
    end
  end
end
