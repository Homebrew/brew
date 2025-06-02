# frozen_string_literal: true
class CGI
  # Base module for HTML-generation mixins.
  #
  # Provides methods for code generation for tags following
  # the various DTD element types.
  module TagMaker # :nodoc:

    # Generate code for an element with required start and end tags.
    #
    #   - -
    def nn_element(element, attributes = {})
      s = nOE_element(element, attributes)
      if block_given?
        s << yield.to_s
      end
      s << "</#{element.upcase}>"
    end

    def nn_element_def(attributes = {}, &block)
      nn_element(__callee__, attributes, &block)
    end

    # Generate code for an empty element.
    #
    #   - O EMPTY
    def nOE_element(element, attributes = {})
      attributes={attributes=>nil} if attributes.kind_of?(String)
      s = "<#{element.upcase}".dup
      attributes.each do|name, value|
        next unless value
        s << " "
        s << CGI.escapeHTML(name.to_s)
        if value != true
          s << '="'
          s << CGI.escapeHTML(value.to_s)
          s << '"'
        end
      end
      s << ">"
    end

    def nOE_element_def(attributes = {}, &block)
      nOE_element(__callee__, attributes, &block)
    end


    # Generate code for an element for which the end (and possibly the
    # start) tag is optional.
    #
    #   O O or - O
    def nO_element(element, attributes = {})
      s = nOE_element(element, attributes)
      if block_given?
        s << yield.to_s
        s << "</#{element.upcase}>"
      end
      s
    end

    def nO_element_def(attributes = {}, &block)
      nO_element(__callee__, attributes, &block)
    end

  end # TagMaker


  # Mixin module providing HTML generation methods.
  #
  # For example,
  #   cgi.a("http://www.example.com") { "Example" }
  #     # => "<A HREF=\"http://www.example.com\">Example</A>"
  #
  # Modules Html3, Html4, etc., contain more basic HTML-generation methods
  # (+#title+, +#h1+, etc.).
  #
  # See class CGI for a detailed example.
  #
  module HtmlExtension


    # Generate an Anchor element as a string.
    #
    # +href+ can either be a string, giving the URL
    # for the HREF attribute, or it can be a hash of
    # the element's attributes.
    #
    # The body of the element is the string returned by the no-argument
    # block passed in.
    #
    #   a("http://www.example.com") { "Example" }
    #     # => "<A HREF=\"http://www.example.com\">Example</A>"
    #
    #   a("HREF" => "http://www.example.com", "TARGET" => "_top") { "Example" }
    #     # => "<A HREF=\"http://www.example.com\" TARGET=\"_top\">Example</A>"
    #
    def a(href = "") # :yield:
      attributes = if href.kind_of?(String)
                     { "HREF" => href }
                   else
                     href
                   end
      super(attributes)
    end

    # Generate a Document Base URI element as a String.
    #
    # +href+ can either by a string, giving the base URL for the HREF
    # attribute, or it can be a has of the element's attributes.
    #
    # The passed-in no-argument block is ignored.
    #
    #   base("http://www.example.com/cgi")
    #     # => "<BASE HREF=\"http://www.example.com/cgi\">"
    def base(href = "") # :yield:
      attributes = if href.kind_of?(String)
                     { "HREF" => href }
                   else
                     href
                   end
      super(attributes)
    end

    # Generate a BlockQuote element as a string.
    #
    # +cite+ can either be a string, give the URI for the source of
    # the quoted text, or a hash, giving all attributes of the element,
    # or it can be omitted, in which case the element has no attributes.
    #
    # The body is provided by the passed-in no-argument block
    #
    #   blockquote("http://www.example.com/quotes/foo.html") { "Foo!" }
    #     #=> "<BLOCKQUOTE CITE=\"http://www.example.com/quotes/foo.html\">Foo!</BLOCKQUOTE>
    def blockquote(cite = {})  # :yield:
      attributes = if cite.kind_of?(String)
                     { "CITE" => cite }
                   else
                     cite
                   end
      super(attributes)
    end


    # Generate a Table Caption element as a string.
    #
    # +align+ can be a string, giving the alignment of the caption
    # (one of top, bottom, left, or right).  It can be a hash of
    # all the attributes of the element.  Or it can be omitted.
    #
    # The body of the element is provided by the passed-in no-argument block.
    #
    #   caption("left") { "Capital Cities" }
    #     # => <CAPTION ALIGN=\"left\">Capital Cities</CAPTION>
    def caption(align = {}) # :yield:
      attributes = if align.kind_of?(String)
                     { "ALIGN" => align }
                   else
                     align
                   end
      super(attributes)
    end


    # Generate a Checkbox Input element as a string.
    #
    # The attributes of the element can be specified as three arguments,
    # +name+, +value+, and +checked+.  +checked+ is a boolean value;
    # if true, the CHECKED attribute will be included in the element.
    #
    # Alternatively, the attributes can be specified as a hash.
    #
    #   checkbox("name")
    #     # = checkbox("NAME" => "name")
    #
    #   checkbox("name", "value")
    #     # = checkbox("NAME" => "name", "VALUE" => "value")
    #
    #   checkbox("name", "value", true)
    #     # = checkbox("NAME" => "name", "VALUE" => "value", "CHECKED" => true)
    def checkbox(name = "", value = nil, checked = nil)
      attributes = if name.kind_of?(String)
                     { "TYPE" => "checkbox", "NAME" => name,
                       "VALUE" => value, "CHECKED" => checked }
                   else
                     name["TYPE"] = "checkbox"
                     name
                   end
      input(attributes)
    end

    # Generate a sequence of checkbox elements, as a String.
    #
    # The checkboxes will all have the same +name+ attribute.
    # Each checkbox is followed by a label.
    # There will be one checkbox for each value.  Each value
    # can be specified as a String, which will be used both
    # as the value of the VALUE attribute and as the label
    # for that checkbox.  A single-element array has the
    # same effect.
    #
    # Each value can also be specified as a three-element array.
    # The first element is the VALUE attribute; the second is the
    # label; and the third is a boolean specifying whether this
    # checkbox is CHECKED.
    #
    # Each value can also be specified as a two-element
    # array, by omitting either the value element (defaults
    # to the same as the label), or the boolean checked element
    # (defaults to false).
    #
    #   checkbox_group("name", "foo", "bar", "baz")
    #     # <INPUT TYPE="checkbox" NAME="name" VALUE="foo">foo
    #     # <INPUT TYPE="checkbox" NAME="name" VALUE="bar">bar
    #     # <INPUT TYPE="checkbox" NAME="name" VALUE="baz">baz
    #
    #   checkbox_group("name", ["foo"], ["bar", true], "baz")
    #     # <INPUT TYPE="checkbox" NAME="name" VALUE="foo">foo
    #     # <INPUT TYPE="checkbox" CHECKED NAME="name" VALUE="bar">bar
    #     # <INPUT TYPE="checkbox" NAME="name" VALUE="baz">baz
    #
    #   checkbox_group("name", ["1", "Foo"], ["2", "Bar", true], "Baz")
    #     # <INPUT TYPE="checkbox" NAME="name" VALUE="1">Foo
    #     # <INPUT TYPE="checkbox" CHECKED NAME="name" VALUE="2">Bar
    #     # <INPUT TYPE="checkbox" NAME="name" VALUE="Baz">Baz
    #
    #   checkbox_group("NAME" => "name",
    #                    "VALUES" => ["foo", "bar", "baz"])
    #
    #   checkbox_group("NAME" => "name",
    #                    "VALUES" => [["foo"], ["bar", true], "baz"])
    #
    #   checkbox_group("NAME" => "name",
    #                    "VALUES" => [["1", "Foo"], ["2", "Bar", true], "Baz"])
    def checkbox_group(name = "", *values)
      if name.kind_of?(Hash)
        values = name["VALUES"]
        name = name["NAME"]
      end
      values.collect{|value|
        if value.kind_of?(String)
          checkbox(name, value) + value
        else
          if value[-1] == true || value[-1] == false
            checkbox(name, value[0],  value[-1]) +
            value[-2]
          else
            checkbox(name, value[0]) +
            value[-1]
          end
        end
      }.join
    end


    # Generate an File Upload Input element as a string.
    #
    # The attributes of the element can be specified as three arguments,
    # +name+, +size+, and +maxlength+.  +maxlength+ is the maximum length
    # of the file's _name_, not of the file's _contents_.
    #
    # Alternatively, the attributes can be specified as a hash.
    #
    # See #multipart_form() for forms that include file uploads.
    #
    #   file_field("name")
    #     # <INPUT TYPE="file" NAME="name" SIZE="20">
    #
    #   file_field("name", 40)
    #     # <INPUT TYPE="file" NAME="name" SIZE="40">
    #
    #   file_field("name", 40, 100)
    #     # <INPUT TYPE="file" NAME="name" SIZE="40" MAXLENGTH="100">
    #
    #   file_field("NAME" => "name", "SIZE" => 40)
    #     # <INPUT TYPE="file" NAME="name" SIZE="40">
    def file_field(name = "", size = 20, maxlength = nil)
      attributes = if name.kind_of?(String)
                     { "TYPE" => "file", "NAME" => name,
                       "SIZE" => size.to_s }
                   else
                     name["TYPE"] = "file"
                     name
                   end
      attributes["MAXLENGTH"] = maxlength.to_s if maxlength
      input(attributes)
    end


    # Generate a Form element as a string.
    #
    # +method+ should be either "get" or "post", and defaults to the latter.
    # +action+ defaults to the current CGI script name.  +enctype+
    # defaults to "application/x-www-form-urlencoded".
    #
    # Alternatively, the attributes can be specified as a hash.
    #
    # See also #multipart_form() for forms that include file uploads.
    #
    #   form{ "string" }
    #     # <FORM METHOD="post" ENCTYPE="application/x-www-form-urlencoded">string</FORM>
    #
    #   form("get") { "string" }
    #     # <FORM METHOD="get" ENCTYPE="application/x-www-form-urlencoded">string</FORM>
    #
    #   form("get", "url") { "string" }
    #     # <FORM METHOD="get" ACTION="url" ENCTYPE="application/x-www-form-urlencoded">string</FORM>
    #
    #   form("METHOD" => "post", "ENCTYPE" => "enctype") { "string" }
    #     # <FORM METHOD="post" ENCTYPE="enctype">string</FORM>
    def form(method = "post", action = script_name, enctype = "application/x-www-form-urlencoded")
      attributes = if method.kind_of?(String)
                     { "METHOD" => method, "ACTION" => action,
                       "ENCTYPE" => enctype }
                   else
                     unless method.has_key?("METHOD")
                       method["METHOD"] = "post"
                     end
                     unless method.has_key?("ENCTYPE")
                       method["ENCTYPE"] = enctype
                     end
                     method
                   end
      if block_given?
        body = yield
      else
        body = ""
      end
      if @output_hidden
        body << @output_hidden.collect{|k,v|
          "<INPUT TYPE=\"HIDDEN\" NAME=\"#{k}\" VALUE=\"#{v}\">"
        }.join
      end
      super(attributes){body}
    end

    # Generate a Hidden Input element as a string.
    #
    # The attributes of the element can be specified as two arguments,
    # +name+ and +value+.
    #
    # Alternatively, the attributes can be specified as a hash.
    #
    #   hidden("name")
    #     # <INPUT TYPE="hidden" NAME="name">
    #
    #   hidden("name", "value")
    #     # <INPUT TYPE="hidden" NAME="name" VALUE="value">
    #
    #   hidden("NAME" => "name", "VALUE" => "reset", "ID" => "foo")
    #     # <INPUT TYPE="hidden" NAME="name" VALUE="value" ID="foo">
    def hidden(name = "", value = nil)
      attributes = if name.kind_of?(String)
                     { "TYPE" => "hidden", "NAME" => name, "VALUE" => value }
                   else
                     name["TYPE"] = "hidden"
                     name
                   end
      input(attributes)
    end

    # Generate a top-level HTML element as a string.
    #
    # The attributes of the element are specified as a hash.  The
    # pseudo-attribute "PRETTY" can be used to specify that the generated
    # HTML string should be indented.  "PRETTY" can also be specified as
    # a string as the sole argument to this method.  The pseudo-attribute
    # "DOCTYPE", if given, is used as the leading DOCTYPE SGML tag; it
    # should include the entire text of this tag, including angle brackets.
    #
    # The body of the html element is supplied as a block.
    #
    #   html{ "string" }
    #     # <!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN"><HTML>string</HTML>
    #
    #   html("LANG" => "ja") { "string" }
    #     # <!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN"><HTML LANG="ja">string</HTML>
    #
    #   html("DOCTYPE" => false) { "string" }
    #     # <HTML>string</HTML>
    #
    #   html("DOCTYPE" => '<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML//EN">') { "string" }
    #     # <!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML//EN"><HTML>string</HTML>
    #
    #   html("PRETTY" => "  ") { "<BODY></BODY>" }
    #     # <!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN">
    #     # <HTML>
    #     #   <BODY>
    #     #   </BODY>
    #     # </HTML>
    #
    #   html("PRETTY" => "\t") { "<BODY></BODY>" }
    #     # <!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN">
    #     # <HTML>
    #     #         <BODY>
    #     #         </BODY>
    #     # </HTML>
    #
    #   html("PRETTY") { "<BODY></BODY>" }
    #     # = html("PRETTY" => "  ") { "<BODY></BODY>" }
    #
    #   html(if $VERBOSE then "PRETTY" end) { "HTML string" }
    #
    def html(attributes = {}) # :yield:
      if nil == attributes
        attributes = {}
      elsif "PRETTY" == attributes
        attributes = { "PRETTY" => true }
      end
      pretty = attributes.delete("PRETTY")
      pretty = "  " if true == pretty
      buf = "".dup

      if attributes.has_key?("DOCTYPE")
        if attributes["DOCTYPE"]
          buf << attributes.delete("DOCTYPE")
        else
          attributes.delete("DOCTYPE")
        end
      else
        buf << doctype
      end

      buf << super(attributes)

      if pretty
        CGI.pretty(buf, pretty)
      else
        buf
      end

    end

    # Generate an Image Button Input element as a string.
    #
    # +src+ is the URL of the image to use for the button.  +name+
    # is the input name.  +alt+ is the alternative text for the image.
    #
    # Alternatively, the attributes can be specified as a hash.
    #
    #   image_button("url")
    #     # <INPUT TYPE="image" SRC="url">
    #
    #   image_button("url", "name", "string")
    #     # <INPUT TYPE="image" SRC="url" NAME="name" ALT="string">
    #
    #   image_button("SRC" => "url", "ALT" => "string")
    #     # <INPUT TYPE="image" SRC="url" ALT="string">
    def image_button(src = "", name = nil, alt = nil)
      attributes = if src.kind_of?(String)
                     { "TYPE" => "image", "SRC" => src, "NAME" => name,
                       "ALT" => alt }
                   else
                     src["TYPE"] = "image"
                     src["SRC"] ||= ""
                     src
                   end
      input(attributes)
    end


    # Generate an Image element as a string.
    #
    # +src+ is the URL of the image.  +alt+ is the alternative text for
    # the image.  +width+ is the width of the image, and +height+ is
    # its height.
    #
    # Alternatively, the attributes can be specified as a hash.
    #
    #   img("src", "alt", 100, 50)
    #     # <IMG SRC="src" ALT="alt" WIDTH="100" HEIGHT="50">
    #
    #   img("SRC" => "src", "ALT" => "alt", "WIDTH" => 100, "HEIGHT" => 50)
    #     # <IMG SRC="src" ALT="alt" WIDTH="100" HEIGHT="50">
    def img(src = "", alt = "", width = nil, height = nil)
      attributes = if src.kind_of?(String)
                     { "SRC" => src, "ALT" => alt }
                   else
                     src
                   end
      attributes["WIDTH"] = width.to_s if width
      attributes["HEIGHT"] = height.to_s if height
      super(attributes)
    end


    # Generate a Form element with multipart encoding as a String.
    #
    # Multipart encoding is used for forms that include file uploads.
    #
    # +action+ is the action to perform.  +enctype+ is the encoding
    # type, which defaults to "multipart/form-data".
    #
    # Alternatively, the attributes can be specified as a hash.
    #
    #   multipart_form{ "string" }
    #     # <FORM METHOD="post" ENCTYPE="multipart/form-data">string</FORM>
    #
    #   multipart_form("url") { "string" }
    #     # <FORM METHOD="post" ACTION="url" ENCTYPE="multipart/form-data">string</FORM>
    def multipart_form(action = nil, enctype = "multipart/form-data")
      attributes = if action == nil
                     { "METHOD" => "post", "ENCTYPE" => enctype }
                   elsif action.kind_of?(String)
                     { "METHOD" => "post", "ACTION" => action,
                       "ENCTYPE" => enctype }
                   else
                     unless action.has_key?("METHOD")
                       action["METHOD"] = "post"
                     end
                     unless action.has_key?("ENCTYPE")
                       action["ENCTYPE"] = enctype
                     end
                     action
                   end
      if block_given?
        form(attributes){ yield }
      else
        form(attributes)
      end
    end


    # Generate a Password Input element as a string.
    #
    # +name+ is the name of the input field.  +value+ is its default
    # value.  +size+ is the size of the input field display.  +maxlength+
    # is the maximum length of the inputted password.
    #
    # Alternatively, attributes can be specified as a hash.
    #
    #   password_field("name")
    #     # <INPUT TYPE="password" NAME="name" SIZE="40">
    #
    #   password_field("name", "value")
    #     # <INPUT TYPE="password" NAME="name" VALUE="value" SIZE="40">
    #
    #   password_field("password", "value", 80, 200)
    #     # <INPUT TYPE="password" NAME="name" VALUE="value" SIZE="80" MAXLENGTH="200">
    #
    #   password_field("NAME" => "name", "VALUE" => "value")
    #     # <INPUT TYPE="password" NAME="name" VALUE="value">
    def password_field(name = "", value = nil, size = 40, maxlength = nil)
      attributes = if name.kind_of?(String)
                     { "TYPE" => "password", "NAME" => name,
                       "VALUE" => value, "SIZE" => size.to_s }
                   else
                     name["TYPE"] = "password"
                     name
                   end
      attributes["MAXLENGTH"] = maxlength.to_s if maxlength
      input(attributes)
    end

    # Generate a Select element as a string.
    #
    # +name+ is the name of the element.  The +values+ are the options that
    # can be selected from the Select menu.  Each value can be a String or
    # a one, two, or three-element Array.  If a String or a one-element
    # Array, this is both the value of that option and the text displayed for
    # it.  If a three-element Array, the elements are the option value, displayed
    # text, and a boolean value specifying whether this option starts as selected.
    # The two-element version omits either the option value (defaults to the same
    # as the display text) or the boolean selected specifier (defaults to false).
    #
    # The attributes and options can also be specified as a hash.  In this
    # case, options are specified as an array of values as described above,
    # with the hash key of "VALUES".
    #
    #   popup_menu("name", "foo", "bar", "baz")
    #     # <SELECT NAME="name">
    #     #   <OPTION VALUE="foo">foo</OPTION>
    #     #   <OPTION VALUE="bar">bar</OPTION>
    #     #   <OPTION VALUE="baz">baz</OPTION>
    #     # </SELECT>
    #
    #   popup_menu("name", ["foo"], ["bar", true], "baz")
    #     # <SELECT NAME="name">
    #     #   <OPTION VALUE="foo">foo</OPTION>
    #     #   <OPTION VALUE="bar" SELECTED>bar</OPTION>
    #     #   <OPTION VALUE="baz">baz</OPTION>
    #     # </SELECT>
    #
    #   popup_menu("name", ["1", "Foo"], ["2", "Bar", true], "Baz")
    #     # <SELECT NAME="name">
    #     #   <OPTION VALUE="1">Foo</OPTION>
    #     #   <OPTION SELECTED VALUE="2">Bar</OPTION>
    #     #   <OPTION VALUE="Baz">Baz</OPTION>
    #     # </SELECT>
    #
    #   popup_menu("NAME" => "name", "SIZE" => 2, "MULTIPLE" => true,
    #               "VALUES" => [["1", "Foo"], ["2", "Bar", true], "Baz"])
    #     # <SELECT NAME="name" MULTIPLE SIZE="2">
    #     #   <OPTION VALUE="1">Foo</OPTION>
    #     #   <OPTION SELECTED VALUE="2">Bar</OPTION>
    #     #   <OPTION VALUE="Baz">Baz</OPTION>
    #     # </SELECT>
    def popup_menu(name = "", *values)

      if name.kind_of?(Hash)
        values   = name["VALUES"]
        size     = name["SIZE"].to_s if name["SIZE"]
        multiple = name["MULTIPLE"]
        name     = name["NAME"]
      else
        size = nil
        multiple = nil
      end

      select({ "NAME" => name, "SIZE" => size,
               "MULTIPLE" => multiple }){
        values.collect{|value|
          if value.kind_of?(String)
            option({ "VALUE" => value }){ value }
          else
            if value[value.size - 1] == true
              option({ "VALUE" => value[0], "SELECTED" => true }){
                value[value.size - 2]
              }
            else
              option({ "VALUE" => value[0] }){
                value[value.size - 1]
              }
            end
          end
        }.join
      }

    end

    # Generates a radio-button Input element.
    #
    # +name+ is the name of the input field.  +value+ is the value of
    # the field if checked.  +checked+ specifies whether the field
    # starts off checked.
    #
    # Alternatively, the attributes can be specified as a hash.
    #
    #   radio_button("name", "value")
    #     # <INPUT TYPE="radio" NAME="name" VALUE="value">
    #
    #   radio_button("name", "value", true)
    #     # <INPUT TYPE="radio" NAME="name" VALUE="value" CHECKED>
    #
    #   radio_button("NAME" => "name", "VALUE" => "value", "ID" => "foo")
    #     # <INPUT TYPE="radio" NAME="name" VALUE="value" ID="foo">
    def radio_button(name = "", value = nil, checked = nil)
      attributes = if name.kind_of?(String)
                     { "TYPE" => "radio", "NAME" => name,
                       "VALUE" => value, "CHECKED" => checked }
                   else
                     name["TYPE"] = "radio"
                     name
                   end
      input(attributes)
    end

    # Generate a sequence of radio button Input elements, as a String.
    #
    # This works the same as #checkbox_group().  However, it is not valid
    # to have more than one radiobutton in a group checked.
    #
    #   radio_group("name", "foo", "bar", "baz")
    #     # <INPUT TYPE="radio" NAME="name" VALUE="foo">foo
    #     # <INPUT TYPE="radio" NAME="name" VALUE="bar">bar
    #     # <INPUT TYPE="radio" NAME="name" VALUE="baz">baz
    #
    #   radio_group("name", ["foo"], ["bar", true], "baz")
    #     # <INPUT TYPE="radio" NAME="name" VALUE="foo">foo
    #     # <INPUT TYPE="radio" CHECKED NAME="name" VALUE="bar">bar
    #     # <INPUT TYPE="radio" NAME="name" VALUE="baz">baz
    #
    #   radio_group("name", ["1", "Foo"], ["2", "Bar", true], "Baz")
    #     # <INPUT TYPE="radio" NAME="name" VALUE="1">Foo
    #     # <INPUT TYPE="radio" CHECKED NAME="name" VALUE="2">Bar
    #     # <INPUT TYPE="radio" NAME="name" VALUE="Baz">Baz
    #
    #   radio_group("NAME" => "name",
    #                 "VALUES" => ["foo", "bar", "baz"])
    #
    #   radio_group("NAME" => "name",
    #                 "VALUES" => [["foo"], ["bar", true], "baz"])
    #
    #   radio_group("NAME" => "name",
    #                 "VALUES" => [["1", "Foo"], ["2", "Bar", true], "Baz"])
    def radio_group(name = "", *values)
      if name.kind_of?(Hash)
        values = name["VALUES"]
        name = name["NAME"]
      end
      values.collect{|value|
        if value.kind_of?(String)
          radio_button(name, value) + value
        else
          if value[-1] == true || value[-1] == false
            radio_button(name, value[0],  value[-1]) +
            value[-2]
          else
            radio_button(name, value[0]) +
            value[-1]
          end
        end
      }.join
    end

    # Generate a reset button Input element, as a String.
    #
    # This resets the values on a form to their initial values.  +value+
    # is the text displayed on the button. +name+ is the name of this button.
    #
    # Alternatively, the attributes can be specified as a hash.
    #
    #   reset
    #     # <INPUT TYPE="reset">
    #
    #   reset("reset")
    #     # <INPUT TYPE="reset" VALUE="reset">
    #
    #   reset("VALUE" => "reset", "ID" => "foo")
    #     # <INPUT TYPE="reset" VALUE="reset" ID="foo">
    def reset(value = nil, name = nil)
      attributes = if (not value) or value.kind_of?(String)
                     { "TYPE" => "reset", "VALUE" => value, "NAME" => name }
                   else
                     value["TYPE"] = "reset"
                     value
                   end
      input(attributes)
    end

    alias scrolling_list popup_menu

    # Generate a submit button Input element, as a String.
    #
    # +value+ is the text to display on the button.  +name+ is the name
    # of the input.
    #
    # Alternatively, the attributes can be specified as a hash.
    #
    #   submit
    #     # <INPUT TYPE="submit">
    #
    #   submit("ok")
    #     # <INPUT TYPE="submit" VALUE="ok">
    #
    #   submit("ok", "button1")
    #     # <INPUT TYPE="submit" VALUE="ok" NAME="button1">
    #
    #   submit("VALUE" => "ok", "NAME" => "button1", "ID" => "foo")
    #     # <INPUT TYPE="submit" VALUE="ok" NAME="button1" ID="foo">
    def submit(value = nil, name = nil)
      attributes = if (not value) or value.kind_of?(String)
                     { "TYPE" => "submit", "VALUE" => value, "NAME" => name }
                   else
                     value["TYPE"] = "submit"
                     value
                   end
      input(attributes)
    end

    # Generate a text field Input element, as a String.
    #
    # +name+ is the name of the input field.  +value+ is its initial
    # value.  +size+ is the size of the input area.  +maxlength+
    # is the maximum length of input accepted.
    #
    # Alternatively, the attributes can be specified as a hash.
    #
    #   text_field("name")
    #     # <INPUT TYPE="text" NAME="name" SIZE="40">
    #
    #   text_field("name", "value")
    #     # <INPUT TYPE="text" NAME="name" VALUE="value" SIZE="40">
    #
    #   text_field("name", "value", 80)
    #     # <INPUT TYPE="text" NAME="name" VALUE="value" SIZE="80">
    #
    #   text_field("name", "value", 80, 200)
    #     # <INPUT TYPE="text" NAME="name" VALUE="value" SIZE="80" MAXLENGTH="200">
    #
    #   text_field("NAME" => "name", "VALUE" => "value")
    #     # <INPUT TYPE="text" NAME="name" VALUE="value">
    def text_field(name = "", value = nil, size = 40, maxlength = nil)
      attributes = if name.kind_of?(String)
                     { "TYPE" => "text", "NAME" => name, "VALUE" => value,
                       "SIZE" => size.to_s }
                   else
                     name["TYPE"] = "text"
                     name
                   end
      attributes["MAXLENGTH"] = maxlength.to_s if maxlength
      input(attributes)
    end

    # Generate a TextArea element, as a String.
    #
    # +name+ is the name of the textarea.  +cols+ is the number of
    # columns and +rows+ is the number of rows in the display.
    #
    # Alternatively, the attributes can be specified as a hash.
    #
    # The body is provided by the passed-in no-argument block
    #
    #   textarea("name")
    #      # = textarea("NAME" => "name", "COLS" => 70, "ROWS" => 10)
    #
    #   textarea("name", 40, 5)
    #      # = textarea("NAME" => "name", "COLS" => 40, "ROWS" => 5)
    def textarea(name = "", cols = 70, rows = 10)  # :yield:
      attributes = if name.kind_of?(String)
                     { "NAME" => name, "COLS" => cols.to_s,
                       "ROWS" => rows.to_s }
                   else
                     name
                   end
      super(attributes)
    end

  end # HtmlExtension


  # Mixin module for HTML version 3 generation methods.
  module Html3 # :nodoc:
    include TagMaker

    # The DOCTYPE declaration for this version of HTML
    def doctype
      %|<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN">|
    end

    instance_method(:nn_element_def).tap do |m|
      # - -
      for element in %w[ A TT I B U STRIKE BIG SMALL SUB SUP EM STRONG
          DFN CODE SAMP KBD VAR CITE FONT ADDRESS DIV CENTER MAP
          APPLET PRE XMP LISTING DL OL UL DIR MENU SELECT TABLE TITLE
          STYLE SCRIPT H1 H2 H3 H4 H5 H6 TEXTAREA FORM BLOCKQUOTE
          CAPTION ]
        define_method(element.downcase, m)
      end
    end

    instance_method(:nOE_element_def).tap do |m|
      # - O EMPTY
      for element in %w[ IMG BASE BASEFONT BR AREA LINK PARAM HR INPUT
          ISINDEX META ]
        define_method(element.downcase, m)
      end
    end

    instance_method(:nO_element_def).tap do |m|
      # O O or - O
      for element in %w[ HTML HEAD BODY P PLAINTEXT DT DD LI OPTION TR
          TH TD ]
        define_method(element.downcase, m)
      end
    end

  end # Html3


  # Mixin module for HTML version 4 generation methods.
  module Html4 # :nodoc:
    include TagMaker

    # The DOCTYPE declaration for this version of HTML
    def doctype
      %|<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">|
    end

    # Initialize the HTML generation methods for this version.
    # - -
    instance_method(:nn_element_def).tap do |m|
      for element in %w[ TT I B BIG SMALL EM STRONG DFN CODE SAMP KBD
        VAR CITE ABBR ACRONYM SUB SUP SPAN BDO ADDRESS DIV MAP OBJECT
        H1 H2 H3 H4 H5 H6 PRE Q INS DEL DL OL UL LABEL SELECT OPTGROUP
        FIELDSET LEGEND BUTTON TABLE TITLE STYLE SCRIPT NOSCRIPT
        TEXTAREA FORM A BLOCKQUOTE CAPTION ]
        define_method(element.downcase, m)
      end
    end

    # - O EMPTY
    instance_method(:nOE_element_def).tap do |m|
      for element in %w[ IMG BASE BR AREA LINK PARAM HR INPUT COL META ]
        define_method(element.downcase, m)
      end
    end

    # O O or - O
    instance_method(:nO_element_def).tap do |m|
      for element in %w[ HTML BODY P DT DD LI OPTION THEAD TFOOT TBODY
          COLGROUP TR TH TD HEAD ]
        define_method(element.downcase, m)
      end
    end

  end # Html4


  # Mixin module for HTML version 4 transitional generation methods.
  module Html4Tr # :nodoc:
    include TagMaker

    # The DOCTYPE declaration for this version of HTML
    def doctype
      %|<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">|
    end

    # Initialise the HTML generation methods for this version.
    # - -
    instance_method(:nn_element_def).tap do |m|
      for element in %w[ TT I B U S STRIKE BIG SMALL EM STRONG DFN
          CODE SAMP KBD VAR CITE ABBR ACRONYM FONT SUB SUP SPAN BDO
          ADDRESS DIV CENTER MAP OBJECT APPLET H1 H2 H3 H4 H5 H6 PRE Q
          INS DEL DL OL UL DIR MENU LABEL SELECT OPTGROUP FIELDSET
          LEGEND BUTTON TABLE IFRAME NOFRAMES TITLE STYLE SCRIPT
          NOSCRIPT TEXTAREA FORM A BLOCKQUOTE CAPTION ]
        define_method(element.downcase, m)
      end
    end

    # - O EMPTY
    instance_method(:nOE_element_def).tap do |m|
      for element in %w[ IMG BASE BASEFONT BR AREA LINK PARAM HR INPUT
          COL ISINDEX META ]
        define_method(element.downcase, m)
      end
    end

    # O O or - O
    instance_method(:nO_element_def).tap do |m|
      for element in %w[ HTML BODY P DT DD LI OPTION THEAD TFOOT TBODY
          COLGROUP TR TH TD HEAD ]
        define_method(element.downcase, m)
      end
    end

  end # Html4Tr


  # Mixin module for generating HTML version 4 with framesets.
  module Html4Fr # :nodoc:
    include TagMaker

    # The DOCTYPE declaration for this version of HTML
    def doctype
      %|<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Frameset//EN" "http://www.w3.org/TR/html4/frameset.dtd">|
    end

    # Initialise the HTML generation methods for this version.
    # - -
    instance_method(:nn_element_def).tap do |m|
      for element in %w[ FRAMESET ]
        define_method(element.downcase, m)
      end
    end

    # - O EMPTY
    instance_method(:nOE_element_def).tap do |m|
      for element in %w[ FRAME ]
        define_method(element.downcase, m)
      end
    end

  end # Html4Fr


  # Mixin module for HTML version 5 generation methods.
  module Html5 # :nodoc:
    include TagMaker

    # The DOCTYPE declaration for this version of HTML
    def doctype
      %|<!DOCTYPE HTML>|
    end

    # Initialise the HTML generation methods for this version.
    # - -
    instance_method(:nn_element_def).tap do |m|
      for element in %w[ SECTION NAV ARTICLE ASIDE HGROUP HEADER
        FOOTER FIGURE FIGCAPTION S TIME U MARK RUBY BDI IFRAME
        VIDEO AUDIO CANVAS DATALIST OUTPUT PROGRESS METER DETAILS
        SUMMARY MENU DIALOG I B SMALL EM STRONG DFN CODE SAMP KBD
        VAR CITE ABBR SUB SUP SPAN BDO ADDRESS DIV MAP OBJECT
        H1 H2 H3 H4 H5 H6 PRE Q INS DEL DL OL UL LABEL SELECT
        FIELDSET LEGEND BUTTON TABLE TITLE STYLE SCRIPT NOSCRIPT
        TEXTAREA FORM A BLOCKQUOTE CAPTION ]
        define_method(element.downcase, m)
      end
    end

    # - O EMPTY
    instance_method(:nOE_element_def).tap do |m|
      for element in %w[ IMG BASE BR AREA LINK PARAM HR INPUT COL META
        COMMAND EMBED KEYGEN SOURCE TRACK WBR ]
        define_method(element.downcase, m)
      end
    end

    # O O or - O
    instance_method(:nO_element_def).tap do |m|
      for element in %w[ HTML HEAD BODY P DT DD LI OPTION THEAD TFOOT TBODY
          OPTGROUP COLGROUP RT RP TR TH TD ]
        define_method(element.downcase, m)
      end
    end

  end # Html5

  class HTML3
    include Html3
    include HtmlExtension
  end

  class HTML4
    include Html4
    include HtmlExtension
  end

  class HTML4Tr
    include Html4Tr
    include HtmlExtension
  end

  class HTML4Fr
    include Html4Tr
    include Html4Fr
    include HtmlExtension
  end

  class HTML5
    include Html5
    include HtmlExtension
  end

end
