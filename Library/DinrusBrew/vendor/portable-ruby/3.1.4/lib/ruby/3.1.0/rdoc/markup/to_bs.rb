# frozen_string_literal: true
##
# Outputs RDoc markup with hot backspace action!  You will probably need a
# pager to use this output format.
#
# This formatter won't work on 1.8.6 because it lacks String#chars.

class RDoc::Markup::ToBs < RDoc::Markup::ToRdoc

  ##
  # Returns a new ToBs that is ready for hot backspace action!

  def initialize markup = nil
    super

    @in_b  = false
    @in_em = false
  end

  ##
  # Sets a flag that is picked up by #annotate to do the right thing in
  # #convert_string

  def init_tags
    add_tag :BOLD, '+b', '-b'
    add_tag :EM,   '+_', '-_'
    add_tag :TT,   ''  , ''   # we need in_tt information maintained
  end

  ##
  # Makes heading text bold.

  def accept_heading heading
    use_prefix or @res << ' ' * @indent
    @res << @headings[heading.level][0]
    @in_b = true
    @res << attributes(heading.text)
    @in_b = false
    @res << @headings[heading.level][1]
    @res << "\n"
  end

  ##
  # Turns on or off regexp handling for +convert_string+

  def annotate tag
    case tag
    when '+b' then @in_b = true
    when '-b' then @in_b = false
    when '+_' then @in_em = true
    when '-_' then @in_em = false
    end
    ''
  end

  ##
  # Calls convert_string on the result of convert_regexp_handling

  def convert_regexp_handling target
    convert_string super
  end

  ##
  # Adds bold or underline mixed with backspaces

  def convert_string string
    return string unless @in_b or @in_em
    chars = if @in_b then
              string.chars.map do |char| "#{char}\b#{char}" end
            elsif @in_em then
              string.chars.map do |char| "_\b#{char}" end
            end

    chars.join
  end

end
