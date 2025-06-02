# frozen_string_literal: true
##
# A singleton class

class RDoc::SingleClass < RDoc::ClassModule

  ##
  # Adds the superclass to the included modules.

  def ancestors
    superclass ? super + [superclass] : super
  end

  def aref_prefix # :nodoc:
    'sclass'
  end

  ##
  # The definition of this singleton class, <tt>class << MyClassName</tt>

  def definition
    "class << #{full_name}"
  end

end

