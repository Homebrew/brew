# typed: strict
# frozen_string_literal: true

require "rubocops/simple_type_assertion"

RSpec.describe RuboCop::Cop::Homebrew::SimpleTypeAssertion, :config do
  sig { returns(RuboCop::Cop::Homebrew::SimpleTypeAssertion) }
  subject(:cop) { described_class.new(configuration) }

  it "flags a ternary in the value passed to T.let" do
    expect_offense(<<~RUBY)
      queue = T.let(dry_run ? nil : Homebrew::DownloadQueue.new(pour: true),
                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Move this expression outside `T.let`.
                    T.nilable(Homebrew::DownloadQueue))
    RUBY
  end

  it "flags calls and operators in the value passed to ::T.cast" do
    expect_offense(<<~RUBY)
      ::T.cast(queues.map(&:first).uniq, Array)
               ^^^^^^^^^^^^^^^^^^^^^^^^ Move this expression outside `T.cast`.
      ::T.cast(options[:queue] || Queue.new, Queue)
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Move this expression outside `T.cast`.
      ::T.cast(size + 2, Integer)
               ^^^^^^^^ Move this expression outside `T.cast`.
    RUBY
  end

  it "flags computations nested in literals" do
    expect_offense(<<~'RUBY')
      T.let({ key: [size + 1] }, T::Hash[Symbol, T::Array[String]])
            ^^^^^^^^^^^^^^^^^^^ Move this expression outside `T.let`.
      T.let("queue-#{@id + 1}", String)
            ^^^^^^^^^^^^^^^^^^ Move this expression outside `T.let`.
    RUBY
  end

  it "classifies the element of a parenthesised array once" do
    allow(cop).to receive(:simple_value?).and_call_original
    expect(cop).to receive(:simple_value?).with(have_attributes(or_type?: true)).once.and_call_original
    inspect_source("T.let(([queue || fallback]), Array)")
  end

  it "classifies the receiver of a unary operator once" do
    allow(cop).to receive(:value_operand?).and_call_original
    expect(cop).to receive(:value_operand?).with(have_attributes(str_type?: true)).once.and_call_original
    inspect_source('T.let(+"", String)')
  end

  it "flags attribute writes and string appends" do
    expect_offense(<<~RUBY)
      T.let(config.mode = :safe, Symbol)
            ^^^^^^^^^^^^^^^^^^^ Move this expression outside `T.let`.
      T.cast(BUFFER << "suffix", String)
             ^^^^^^^^^^^^^^^^^^ Move this expression outside `T.cast`.
    RUBY
  end

  it "accepts lookups and conversions within three calls and arguments" do
    expect_no_offenses(<<~RUBY)
      T.let(Array(:settings), Array)
      T.let(data.dig(:settings), Array)
      T.let(Array(data.dig(:settings)), Array)
      T.let(data.dig(:settings, :aliases), Array)
      T.let((config.queue.name.to_s).freeze, String)
      T.let(Queue.new(mode: :safe, size: 2), Queue)
    RUBY
  end

  it "allows parentheses around integer shift receivers" do
    expect_offense(<<~RUBY)
      T.let(1 << SHIFT, Integer)
      T.let((1) << SHIFT, Integer)
      T.cast(((1)) << SHIFT, Integer)
      T.let(("buffer") << SHIFT, String)
            ^^^^^^^^^^^^^^^^^^^ Move this expression outside `T.let`.
      T.let((0; 1) << SHIFT, Integer)
            ^^^^^^^^^^^^^^^ Move this expression outside `T.let`.
    RUBY
  end

  it "applies the receiver's complexity limit and operand rules through &.freeze" do
    expect_offense(<<~RUBY)
      T.let(config.queue.name.to_s&.freeze, T.nilable(String))
      T.cast(build_queue(:safe)&.freeze, T.nilable(Queue))
      T.let(Array(build_queue(:safe)&.freeze), Array)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Move this expression outside `T.let`.
    RUBY
  end

  it "accepts a deferred block declared with Proc.new" do
    expect_no_offenses(<<~RUBY)
      T.let(Proc.new { value }, Proc)
      T.let(::Proc.new { value }, Proc)
      T.let(proc { |item| item.name }, Proc)
      T.let(-> { _1.name }, Proc)
    RUBY
  end

  it "flags expressions over budget and logic inside deferred blocks" do
    expect_offense(<<~RUBY)
      T.let(Array(data.dig(:settings, :aliases)), Array)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Move this expression outside `T.let`.
      T.let(Proc.new { value || fallback }, Proc)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Move this expression outside `T.let`.
      T.let(Hash.new { |h, k| h[k] = [] }, Hash)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Move this expression outside `T.let`.
      T.let(Queue.new(mode: :safe, size: 2, log: true), Queue)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Move this expression outside `T.let`.
      T.let(Proc.new { config.queue.name.to_s }, Proc)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Move this expression outside `T.let`.
      T.cast(config.queue.name.to_s.strip, String)
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Move this expression outside `T.cast`.
      T.cast(-> { value || fallback }, Proc)
             ^^^^^^^^^^^^^^^^^^^^^^^^ Move this expression outside `T.cast`.
    RUBY
  end

  it "flags branching inside parentheses, complex lookup keys and blocks on other constructors" do
    expect_offense(<<~RUBY)
      T.let(([queue || fallback]), Array)
            ^^^^^^^^^^^^^^^^^^^^^ Move this expression outside `T.let`.
      T.let(data.dig(key || fallback), Array)
            ^^^^^^^^^^^^^^^^^^^^^^^^^ Move this expression outside `T.let`.
      T.let(Custom::Proc.new { value }, Object)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^ Move this expression outside `T.let`.
    RUBY
  end

  it "accepts variables, constants and literal values with compound types" do
    allow(self).to receive(:ruby_version).and_return(4.0)

    expect_no_offenses(<<~'RUBY')
      queue = T.let(nil, T.nilable(Homebrew::DownloadQueue))
      queue ||= Homebrew::DownloadQueue.new unless dry_run
      T.let(Homebrew::DownloadQueue.new(pour: true), Queue)
      T.cast(queue, T.nilable(Queue))
      T.cast(queues.fetch(key), Queue)
      T.cast(queues[key], Queue)
      T.let(Array(data[:aliases]), T::Array[String])
      T.let(Pathname(paths.fetch(:home)), Pathname)
      T.let(+"", String)
      T.let([:one, :two].freeze, T::Array[Symbol])
      T.let(Hash.new { [] }, T::Hash[String, T::Array[String]])
      T.cast((@queue), T.any(Queue, Array))
      T.let([*DEFAULTS, queue.name].freeze, T::Array[String])
      T.let("queue-#{@id}", String)
      T.let((CACHE/"api").freeze, Pathname)
      T.let(64 * 1024, Integer)
      T.let(nil, T.nilable(String))
      T.let(::Homebrew::DEFAULT, String)
      T.let(-> { value }, Proc)
      def forwarded(&)
        T.cast(build_queue(&), Queue)
      end
      T.let({ keys: [1, :two, false, /three/i] }, T::Hash[Symbol, T::Array[Object]])
    RUBY
  end

  it "ignores other receivers and Sorbet methods" do
    expect_no_offenses(<<~RUBY)
      let(:queue) { build_queue }
      Other::T.let(queue || build_queue, Queue)
      model.cast(queue || build_queue, Queue)
      T.must(queue || build_queue)
    RUBY
  end
end
