# frozen_string_literal: true
##
# RDoc::CrossReference is a reusable way to create cross references for names.

class RDoc::CrossReference

  ##
  # Regular expression to match class references
  #
  # 1. There can be a '\\' in front of text to suppress the cross-reference
  # 2. There can be a '::' in front of class names to reference from the
  #    top-level namespace.
  # 3. The method can be followed by parenthesis (not recommended)

  CLASS_REGEXP_STR = '\\\\?((?:\:{2})?[A-Z]\w*(?:\:\:\w+)*)'

  ##
  # Regular expression to match method references.
  #
  # See CLASS_REGEXP_STR

  METHOD_REGEXP_STR = '([A-Za-z]\w*[!?=]?|%|===?|\[\]=?|<<|>>|\+@|-@|-|\+|\*)(?:\([\w.+*/=<>-]*\))?'

  ##
  # Regular expressions matching text that should potentially have
  # cross-reference links generated are passed to add_regexp_handling. Note
  # that these expressions are meant to pick up text for which cross-references
  # have been suppressed, since the suppression characters are removed by the
  # code that is triggered.

  CROSSREF_REGEXP = /(?:^|[\s()])
                     (
                      (?:
                       # A::B::C.meth
                       #{CLASS_REGEXP_STR}(?:[.#]|::)#{METHOD_REGEXP_STR}

                       # A::B::C
                       # The stuff after CLASS_REGEXP_STR is a
                       # nasty hack.  CLASS_REGEXP_STR unfortunately matches
                       # words like dog and cat (these are legal "class"
                       # names in Fortran 95).  When a word is flagged as a
                       # potential cross-reference, limitations in the markup
                       # engine suppress other processing, such as typesetting.
                       # This is particularly noticeable for contractions.
                       # In order that words like "can't" not
                       # be flagged as potential cross-references, only
                       # flag potential class cross-references if the character
                       # after the cross-reference is a space, sentence
                       # punctuation, tag start character, or attribute
                       # marker.
                       | #{CLASS_REGEXP_STR}(?=[@\s).?!,;<\000]|\z)

                       # Stand-alone method (preceded by a #)
                       | \\?\##{METHOD_REGEXP_STR}

                       # Stand-alone method (preceded by ::)
                       | ::#{METHOD_REGEXP_STR}

                       # Things that look like filenames
                       # The key thing is that there must be at least
                       # one special character (period, slash, or
                       # underscore).
                       | (?:\.\.\/)*[-\/\w]+[_\/.][-\w\/.]+

                       # Things that have markup suppressed
                       # Don't process things like '\<' in \<tt>, though.
                       # TODO: including < is a hack, not very satisfying.
                       | \\[^\s<]
                      )

                      # labels for headings
                      (?:@[\w+%-]+(?:\.[\w|%-]+)?)?
                     )/x

  ##
  # Version of CROSSREF_REGEXP used when <tt>--hyperlink-all</tt> is specified.

  ALL_CROSSREF_REGEXP = /
                     (?:^|[\s()])
                     (
                      (?:
                       # A::B::C.meth
                       #{CLASS_REGEXP_STR}(?:[.#]|::)#{METHOD_REGEXP_STR}

                       # A::B::C
                       | #{CLASS_REGEXP_STR}(?=[@\s).?!,;<\000]|\z)

                       # Stand-alone method
                       | \\?#{METHOD_REGEXP_STR}

                       # Things that look like filenames
                       | (?:\.\.\/)*[-\/\w]+[_\/.][-\w\/.]+

                       # Things that have markup suppressed
                       | \\[^\s<]
                      )

                      # labels for headings
                      (?:@[\w+%-]+)?
                     )/x

  ##
  # Hash of references that have been looked-up to their replacements

  attr_accessor :seen

  ##
  # Allows cross-references to be created based on the given +context+
  # (RDoc::Context).

  def initialize context
    @context = context
    @store   = context.store

    @seen = {}
  end

  def resolve_method name
    ref = nil

    if /#{CLASS_REGEXP_STR}([.#]|::)#{METHOD_REGEXP_STR}/o =~ name then
      type = $2
      if '.' == type # will find either #method or ::method
        method = $3
      else
        method = "#{type}#{$3}"
      end
      container = @context.find_symbol_module($1)
    elsif /^([.#]|::)#{METHOD_REGEXP_STR}/o =~ name then
      type = $1
      if '.' == type
        method = $2
      else
        method = "#{type}#{$2}"
      end
      container = @context
    else
      type = nil
      container = nil
    end

    if container then
      unless RDoc::TopLevel === container then
        if '.' == type then
          if 'new' == method then # AnyClassName.new will be class method
            ref = container.find_local_symbol method
            ref = container.find_ancestor_local_symbol method unless ref
          else
            ref = container.find_local_symbol "::#{method}"
            ref = container.find_ancestor_local_symbol "::#{method}" unless ref
            ref = container.find_local_symbol "##{method}" unless ref
            ref = container.find_ancestor_local_symbol "##{method}" unless ref
          end
        else
          ref = container.find_local_symbol method
          ref = container.find_ancestor_local_symbol method unless ref
        end
      end
    end

    ref
  end

  ##
  # Returns a reference to +name+.
  #
  # If the reference is found and +name+ is not documented +text+ will be
  # returned.  If +name+ is escaped +name+ is returned.  If +name+ is not
  # found +text+ is returned.

  def resolve name, text
    return @seen[name] if @seen.include? name

    ref = case name
          when /^\\(#{CLASS_REGEXP_STR})$/o then
            @context.find_symbol $1
          else
            @context.find_symbol name
          end

    ref = resolve_method name unless ref

    # Try a page name
    ref = @store.page name if not ref and name =~ /^[\w.]+$/

    ref = nil if RDoc::Alias === ref # external alias, can't link to it

    out = if name == '\\' then
            name
          elsif name =~ /^\\/ then
            # we remove the \ only in front of what we know:
            # other backslashes are treated later, only outside of <tt>
            ref ? $' : name
          elsif ref then
            if ref.display? then
              ref
            else
              text
            end
          else
            text
          end

    @seen[name] = out

    out
  end

end

