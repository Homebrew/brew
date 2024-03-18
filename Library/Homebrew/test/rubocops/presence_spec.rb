# frozen_string_literal: true

require "rubocops/presence"

RSpec.describe RuboCop::Cop::Homebrew::Presence, :config do
  it "registers an offense and corrects when `a.present? ? a : nil`" do
    expect_offense(<<~RUBY)
      a.present? ? a : nil
      ^^^^^^^^^^^^^^^^^^^^ Use `a.presence` instead of `a.present? ? a : nil`.
    RUBY

    expect_correction(<<~RUBY)
      a.presence
    RUBY
  end

  it "registers an offense and corrects when `!a.present? ? nil: a`" do
    expect_offense(<<~RUBY)
      !a.present? ? nil: a
      ^^^^^^^^^^^^^^^^^^^^ Use `a.presence` instead of `!a.present? ? nil: a`.
    RUBY

    expect_correction(<<~RUBY)
      a.presence
    RUBY
  end

  it "registers an offense and corrects when `a.blank? ? nil : a`" do
    expect_offense(<<~RUBY)
      a.blank? ? nil : a
      ^^^^^^^^^^^^^^^^^^ Use `a.presence` instead of `a.blank? ? nil : a`.
    RUBY

    expect_correction(<<~RUBY)
      a.presence
    RUBY
  end

  it "registers an offense and corrects when `!a.blank? ? a : nil`" do
    expect_offense(<<~RUBY)
      !a.blank? ? a : nil
      ^^^^^^^^^^^^^^^^^^^ Use `a.presence` instead of `!a.blank? ? a : nil`.
    RUBY

    expect_correction(<<~RUBY)
      a.presence
    RUBY
  end

  it "registers an offense and corrects when `a.present? ? a : b`" do
    expect_offense(<<~RUBY)
      a.present? ? a : b
      ^^^^^^^^^^^^^^^^^^ Use `a.presence || b` instead of `a.present? ? a : b`.
    RUBY

    expect_correction(<<~RUBY)
      a.presence || b
    RUBY
  end

  it "registers an offense and corrects when `!a.present? ? b : a`" do
    expect_offense(<<~RUBY)
      !a.present? ? b : a
      ^^^^^^^^^^^^^^^^^^^ Use `a.presence || b` instead of `!a.present? ? b : a`.
    RUBY

    expect_correction(<<~RUBY)
      a.presence || b
    RUBY
  end

  it "registers an offense and corrects when `a.blank? ? b : a`" do
    expect_offense(<<~RUBY)
      a.blank? ? b : a
      ^^^^^^^^^^^^^^^^ Use `a.presence || b` instead of `a.blank? ? b : a`.
    RUBY

    expect_correction(<<~RUBY)
      a.presence || b
    RUBY
  end

  it "registers an offense and corrects when `!a.blank? ? a : b`" do
    expect_offense(<<~RUBY)
      !a.blank? ? a : b
      ^^^^^^^^^^^^^^^^^ Use `a.presence || b` instead of `!a.blank? ? a : b`.
    RUBY

    expect_correction(<<~RUBY)
      a.presence || b
    RUBY
  end

  it "registers an offense and corrects when `a.present? ? a : 1`" do
    expect_offense(<<~RUBY)
      a.present? ? a : 1
      ^^^^^^^^^^^^^^^^^^ Use `a.presence || 1` instead of `a.present? ? a : 1`.
    RUBY

    expect_correction(<<~RUBY)
      a.presence || 1
    RUBY
  end

  it "registers an offense and corrects when `a.blank? ? 1 : a`" do
    expect_offense(<<~RUBY)
      a.blank? ? 1 : a
      ^^^^^^^^^^^^^^^^ Use `a.presence || 1` instead of `a.blank? ? 1 : a`.
    RUBY

    expect_correction(<<~RUBY)
      a.presence || 1
    RUBY
  end

  it "registers an offense and corrects when `a(:bar).map(&:baz).present? ? a(:bar).map(&:baz) : nil`" do
    expect_offense(<<~RUBY)
      a(:bar).map(&:baz).present? ? a(:bar).map(&:baz) : nil
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `a(:bar).map(&:baz).presence` instead of `a(:bar).map(&:baz).present? ? a(:bar).map(&:baz) : nil`.
    RUBY

    expect_correction(<<~RUBY)
      a(:bar).map(&:baz).presence
    RUBY
  end

  it "registers an offense and corrects when `a.present? ? a : b[:c]`" do
    expect_offense(<<~RUBY)
      a.present? ? a : b[:c]
      ^^^^^^^^^^^^^^^^^^^^^^ Use `a.presence || b[:c]` instead of `a.present? ? a : b[:c]`.
    RUBY

    expect_correction(<<~RUBY)
      a.presence || b[:c]
    RUBY
  end

  it "registers an offense and corrects when multi-line if node" do
    expect_offense(<<~RUBY)
      if a.present?
      ^^^^^^^^^^^^^ Use `a.presence` instead of `if a.present? ... end`.
        a
      else
        nil
      end
    RUBY

    expect_correction(<<~RUBY)
      a.presence
    RUBY
  end

  it "registers an offense and corrects when multi-line unless node" do
    expect_offense(<<~RUBY)
      unless a.present?
      ^^^^^^^^^^^^^^^^^ Use `a.presence` instead of `unless a.present? ... end`.
        nil
      else
        a
      end
    RUBY

    expect_correction(<<~RUBY)
      a.presence
    RUBY
  end

  it "registers an offense and corrects when multi-line if node with `+` operators in the else branch" do
    expect_offense(<<~RUBY)
      if a.present?
      ^^^^^^^^^^^^^ Use `a.presence || b.to_f + 12.0` instead of `if a.present? ... end`.
        a
      else
        b.to_f + 12.0
      end
    RUBY

    expect_correction(<<~RUBY)
      a.presence || b.to_f + 12.0
    RUBY
  end

  it "registers an offense and corrects when multi-line if `*` operators in the else branch" do
    expect_offense(<<~RUBY)
      if a.present?
      ^^^^^^^^^^^^^ Use `a.presence || b.to_f * 12.0` instead of `if a.present? ... end`.
        a
      else
        b.to_f * 12.0
      end
    RUBY

    expect_correction(<<~RUBY)
      a.presence || b.to_f * 12.0
    RUBY
  end

  it "registers an offense and corrects when `a if a.present?`" do
    expect_offense(<<~RUBY)
      a if a.present?
      ^^^^^^^^^^^^^^^ Use `a.presence` instead of `a if a.present?`.
    RUBY

    expect_correction(<<~RUBY)
      a.presence
    RUBY
  end

  it "registers an offense and corrects when `a unless a.blank?`" do
    expect_offense(<<~RUBY)
      a unless a.blank?
      ^^^^^^^^^^^^^^^^^ Use `a.presence` instead of `a unless a.blank?`.
    RUBY

    expect_correction(<<~RUBY)
      a.presence
    RUBY
  end

  it "registers an offense and corrects when `.present?` with method chain" do
    expect_offense(<<~RUBY)
      if [1, 2, 3].map { |num| num + 1 }
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `[1, 2, 3].map { |num| num + 1 }.map { |num| num + 2 }.presence || b` instead of `if [1, 2, 3].map { |num| num + 1 }.map { |num| num + 2 }.present? ... end`.
                  .map { |num| num + 2 }
                  .present?
                  [1, 2, 3].map { |num| num + 1 }.map { |num| num + 2 }
      else
        b
      end
    RUBY

    expect_correction(<<~RUBY)
      [1, 2, 3].map { |num| num + 1 }
                  .map { |num| num + 2 }.presence || b
    RUBY
  end

  context "when multiline ternary can be replaced" do
    it "registers an offense and corrects" do
      expect_offense(<<~RUBY)
        a.present? ?
        ^^^^^^^^^^^^ Use `a.presence` instead of `a.present? ? a : nil`.
          a :
          nil
      RUBY

      expect_correction(<<~RUBY)
        a.presence
      RUBY
    end
  end

  context "when a method argument of `else` branch is enclosed in parentheses" do
    it "registers an offense and corrects" do
      expect_offense(<<~RUBY)
        if value.present?
        ^^^^^^^^^^^^^^^^^ Use `value.presence || do_something(value)` instead of `if value.present? ... end`.
          value
        else
          do_something(value)
        end
      RUBY

      expect_correction(<<~RUBY)
        value.presence || do_something(value)
      RUBY
    end
  end

  context "when a method argument of `else` branch is not enclosed in parentheses" do
    it "registers an offense and corrects" do
      expect_offense(<<~RUBY)
        if value.present?
        ^^^^^^^^^^^^^^^^^ Use `value.presence || do_something(value)` instead of `if value.present? ... end`.
          value
        else
          do_something value
        end
      RUBY

      expect_correction(<<~RUBY)
        value.presence || do_something(value)
      RUBY
    end
  end

  context "when multiple method arguments of `else` branch is not enclosed in parentheses" do
    it "registers an offense and corrects" do
      expect_offense(<<~RUBY)
        if value.present?
        ^^^^^^^^^^^^^^^^^ Use `value.presence || do_something(arg1, arg2)` instead of `if value.present? ... end`.
          value
        else
          do_something arg1, arg2
        end
      RUBY

      expect_correction(<<~RUBY)
        value.presence || do_something(arg1, arg2)
      RUBY
    end
  end

  context "when a method argument with a receiver of `else` branch is not enclosed in parentheses" do
    it "registers an offense and corrects" do
      expect_offense(<<~RUBY)
        if value.present?
        ^^^^^^^^^^^^^^^^^ Use `value.presence || foo.do_something(value)` instead of `if value.present? ... end`.
          value
        else
          foo.do_something value
        end
      RUBY

      expect_correction(<<~RUBY)
        value.presence || foo.do_something(value)
      RUBY
    end
  end

  context "when a right-hand side of the relational operator" do
    %w[< > <= >= == !=].each do |operator|
      it "registers an offense and corrects when `#{operator}`" do
        expect_offense(<<~RUBY, operator:)
          a #{operator} if b.present?
            _{operator} ^^^^^^^^^^^^^ Use `(b.presence || c)` instead of `if b.present? ... end`.
            b
          else
            c
          end
        RUBY

        expect_correction(<<~RUBY)
          a #{operator} (b.presence || c)
        RUBY
      end
    end
  end

  it "does not register an offense when using `#presence`" do
    expect_no_offenses(<<~RUBY)
      a.presence
    RUBY
  end

  it "does not register an offense when the expression does not return the receiver of `#present?`" do
    expect_no_offenses(<<~RUBY)
      a.present? ? b : nil
    RUBY

    expect_no_offenses(<<~RUBY)
      puts foo if present?
      puts foo if !present?
    RUBY
  end

  it "does not register an offense when the expression does not return the receiver of `#blank?`" do
    expect_no_offenses(<<~RUBY)
      a.blank? ? nil : b
    RUBY

    expect_no_offenses(<<~RUBY)
      puts foo if blank?
      puts foo if !blank?
    RUBY
  end

  it "does not register an offense when if or unless modifier is used" do
    [
      "a if a.blank?",
      "a unless a.present?",
    ].each { |source| expect_no_offenses(source) }
  end

  it "does not register an offense when the else block is multiline" do
    expect_no_offenses(<<~RUBY)
      if a.present?
        a
      else
        something
        something
        something
      end
    RUBY
  end

  it "does not register an offense when the else block has multiple statements" do
    expect_no_offenses(<<~RUBY)
      if a.present?
        a
      else
        something; something; something
      end
    RUBY
  end

  it "does not register an offense when including the elsif block" do
    expect_no_offenses(<<~RUBY)
      if a.present?
        a
      elsif b
        b
      end
    RUBY
  end

  it "does not register an offense when the else block has `if` node" do
    expect_no_offenses(<<~RUBY)
      if a.present?
        a
      else
        b if c
      end
    RUBY
  end

  it "does not register an offense when the else block has `rescue` node" do
    expect_no_offenses(<<~RUBY)
      if something_method.present?
        something_method
      else
        invalid_method rescue StandardError
      end
    RUBY
  end

  it "does not register an offense when the else block has `while` node" do
    expect_no_offenses(<<~RUBY)
      if a.present?
        a
      else
        fetch_state while waiting?
      end
    RUBY
  end

  it "does not register an offense when using #present? with elsif block" do
    expect_no_offenses(<<~RUBY)
      if something?
        a
      elsif b.present?
        b
      end
    RUBY
  end
end
