# typed: true
# frozen_string_literal: true

require "download_queue"

RSpec.describe Homebrew::DownloadQueue do
  subject(:download_queue) { described_class.new }

  let(:cached_download) { HOMEBREW_CACHE/"downloads/testball--0.1.tar.gz" }
  let(:downloadable) do
    instance_double(
      Downloadable,
      cached_download:,
      checksum:                        nil,
      downloaded_and_valid?:           false,
      downloader:                      nil,
      download_queue_message:          "Bottle testball",
      download_queue_name:             "testball",
      download_queue_type:             "Bottle",
      staged_path_from_download_queue: nil,
    )
  end
  let(:download_error) { DownloadError.new(downloadable, RuntimeError.new("network blew up")) }
  let(:multi_line_download_error) { DownloadError.new(downloadable, RuntimeError.new("line one\nline two")) }
  let(:retryable_download) { instance_double(Homebrew::RetryableDownload) }

  before do
    allow(Homebrew::EnvConfig).to receive(:download_concurrency).and_return(2)
    allow(retryable_download).to receive(:fetch).and_raise(download_error)
    allow(Homebrew::RetryableDownload).to receive(:new).and_return(retryable_download)
  end

  after do
    download_queue.shutdown
  end

  describe "#with_progress" do
    before do
      allow($stdout).to receive(:tty?).and_return(true)
      ENV["TERM"] = "xterm-256color"
      allow(downloadable).to receive(:fetched_size).and_return(nil)
    end

    it "displays new downloads before preparation or downloading finishes" do
      displayed = Queue.new
      both_displayed = Queue.new
      release_download = Queue.new
      second_download = instance_double(
        Downloadable,
        cached_download:                 HOMEBREW_CACHE/"downloads/second.tar.gz",
        downloaded_and_valid?:           false,
        downloader:                      nil,
        download_queue_message:          "Bottle second",
        staged_path_from_download_queue: nil,
        fetched_size:                    nil,
      )
      allow(retryable_download).to receive(:fetch) { release_download.pop }
      allow($stdout).to receive(:print) do |message|
        displayed << message if message.include?("Bottle testball")
        both_displayed << message if message.include?("Bottle testball") && message.include?("Bottle second")
      end

      download_queue.with_progress do
        download_queue.enqueue(downloadable)
        first_frame = displayed.pop(timeout: 2)
        download_queue.enqueue(second_download)
        expect([first_frame, both_displayed.pop(timeout: 2)])
          .to match([include("Bottle testball"), include("Bottle testball", "Bottle second")])
      end
    ensure
      2.times { release_download&.push(cached_download) }
    end

    it "clears progress before preparation output and resumes rendering" do
      displayed = Queue.new
      redrawn = Queue.new
      release_download = Queue.new
      output = +""
      allow($stderr).to receive(:tty?).and_return(true)
      allow(File).to receive(:identical?).and_call_original
      allow(File).to receive(:identical?).with($stdout, $stderr).and_return(true)
      allow(retryable_download).to receive(:fetch) { release_download.pop }
      allow($stdout).to receive(:print) do |message|
        output << message
        displayed << true if message.include?("Bottle testball")
        redrawn << true if message.include?("Bottle testball") && output.include?("preparation warning\n")
      end
      allow($stderr).to receive(:write) do |message|
        output << message
        message.bytesize
      end

      download_queue.with_progress do
        download_queue.enqueue(downloadable)
        displayed.pop(timeout: 2)
        $stderr.puts "preparation warning"
        redrawn.pop(timeout: 2)
      end

      expect(output).to match(/Bottle testball.*\e\[Jpreparation warning\n.*Bottle testball/m)
    ensure
      release_download&.push(cached_download)
    end

    it "resumes progress when a manifest fetch completes a partial line" do
      displayed = Queue.new
      release_download = Queue.new
      manifest = instance_double(
        Resource::BottleManifest,
        cached_download:        HOMEBREW_CACHE/"downloads/manifest.json",
        downloaded_and_valid?:  true,
        downloader:             nil,
        download_queue_message: "Bottle Manifest testball",
        fetched_size:           nil,
      )
      allow(manifest).to receive(:is_a?) { |klass| klass == Resource::BottleManifest }
      allow(retryable_download).to receive(:fetch) { release_download.pop }
      allow($stdout).to receive(:print) do |message|
        displayed << true if message.include?("Bottle testball")
      end
      allow($stdout).to receive(:write, &:bytesize)

      download_queue.with_progress do
        download_queue.enqueue(downloadable)
        displayed.pop(timeout: 2)
        $stdout.print "Preparing"
        displayed.clear
        download_queue.enqueue(manifest)
        download_queue.fetch(only: Resource::BottleManifest, heading: "Manifests")
        expect(displayed.pop(timeout: 2)).to be true
      end
    ensure
      release_download&.push(cached_download)
    end

    it "retains coloured completion rows above active downloads without repeating them at fetch" do
      allow(Tty).to receive_messages(color?: true, height: 1)
      active_download = instance_double(Downloadable, download_queue_message: "Bottle active", fetched_size: nil)
      first_future = Concurrent::Promises.resolvable_future
      active_future = Concurrent::Promises.resolvable_future
      download_queue.downloads[downloadable] = first_future
      download_queue.downloads[active_download] = active_future
      frames = Queue.new
      output = +""
      frame = +""
      allow($stdout).to receive(:print) do |message|
        output << message
        frame << message
        if message == Tty.end_synchronized_update
          frames << frame
          frame = +""
        end
      end
      allow($stdout).to receive(:puts) do |*messages|
        message = "#{messages.join("\n")}\n"
        output << message
        frame << message
      end

      first_frame = T.let(nil, T.nilable(String))
      completed_frame = T.let(nil, T.nilable(String))
      download_queue.with_progress do
        first_frame = frames.pop(timeout: 2)
        first_future.fulfill(cached_download)
        completed_frame = Timeout.timeout(2) do
          loop do
            rendered = frames.pop
            break rendered if rendered.include?("\e[32m\u2714\uFE0E\e[0m Bottle testball\n")
          end
        end
        frames.pop(timeout: 2)
        active_future.fulfill(cached_download)
        Timeout.timeout(2) do
          loop { break if frames.pop.include?("\e[32m\u2714\uFE0E\e[0m Bottle active\n") }
        end
      end
      download_queue.fetch(heading: "Downloading bottles")

      expect([first_frame, completed_frame, Tty.strip_ansi(output).scan("Bottle testball\n").length]).to match([
        /\e\[34m.\e\[0m Bottle testball/,
        /\e\[32m\u2714\uFE0E\e\[0m Bottle testball\n.*\e\[34m.\e\[0m Bottle active/m,
        1,
      ])
      expect(output).not_to include("Downloading bottles")
    end

    it "retries unwritten completion rows without repeating rows already printed" do
      second_download = instance_double(Downloadable, download_queue_message: "Bottle second", fetched_size: nil)
      download_queue.downloads[downloadable] = Concurrent::Promises.fulfilled_future(cached_download)
      download_queue.downloads[second_download] = Concurrent::Promises.fulfilled_future(cached_download)
      failed = Queue.new
      output = +""
      allow($stdout).to receive(:print) { |message| output << message }
      allow($stdout).to receive(:puts) do |*messages|
        messages.flatten.each do |message|
          if message.include?("Bottle second")
            failed << true
            raise Errno::EIO
          end
          output << "#{message}\n"
        end
      end

      download_queue.with_progress do
        raise "renderer did not attempt completion output" unless failed.pop(timeout: 2)
      end
      download_queue.fetch

      expect([output.scan("Bottle testball\n").length, output.scan("Bottle second\n").length]).to eq([1, 1])
    end
  end

  describe "progress output" do
    let(:frames) { Queue.new }
    let(:render_attempts) { Queue.new }
    let(:render_event) { Concurrent::Event.new }
    let(:progress) do
      Homebrew::DownloadQueue::Progress.new do
        frames << true
        [[], ["active download"]]
      end
    end

    before do
      download_queue
      allow($stdout).to receive(:print)
      allow($stdout).to receive(:write, &:bytesize)
      allow($stderr).to receive(:write, &:bytesize)
      allow(Concurrent::Event).to receive(:new).and_return(render_event)
      allow(render_event).to receive(:wait).and_wrap_original do |wait, timeout|
        render_attempts << true
        wait.call(timeout)
      end
    end

    it "pauses render attempts during fetch and resumes afterwards" do
      paused_frames = T.let(nil, T.nilable(Integer))
      allow(progress).to receive(:resume).and_wrap_original do |resume|
        frames.clear
        render_attempts.clear
        # Two wait entries guarantee a render-loop iteration between them.
        2.times { raise "renderer did not attempt a refresh" unless render_attempts.pop(timeout: 2) }
        paused_frames = frames.size
        resume.call
      end

      progress.run do
        frames.pop(timeout: 2)
        download_queue.fetch
        expect([paused_frames, frames.pop(timeout: 2)]).to eq([0, true])
      end
    end

    test_each([false, true]) do |stderr_tty|
      it "ignores stderr on a separate #{stderr_tty ? "terminal" : "log"} when tracking partial lines" do
        allow($stderr).to receive(:tty?).and_return(stderr_tty)
        allow(File).to receive(:identical?).and_call_original
        allow(File).to receive(:identical?).with($stdout, $stderr).and_return(false)

        progress.run do
          frames.pop(timeout: 2)
          $stdout.print "Preparing"
          frames.clear
          $stderr.puts "warning"
          render_attempts.clear
          2.times { raise "renderer did not attempt a refresh" unless render_attempts.pop(timeout: 2) }
          premature_frames = frames.size
          $stdout.puts " done"

          expect([premature_frames, frames.pop(timeout: 2)]).to eq([0, true])
        end
      end
    end

    test_each([IOError, Errno::EPIPE, Errno::EIO]) do |error|
      it "tolerates #{error} when clearing a visible frame" do
        expect($stdout).to receive(:print).with("#{Tty.move_cursor_beginning}#{Tty.clear_to_end_of_screen}")
                                          .at_least(:once).and_raise(error)

        expect do
          progress.run do
            raise "renderer did not display a frame" unless frames.pop(timeout: 2)

            progress.pause
            progress.resume
          end
        end.not_to raise_error
      end
    end
  end

  it "does not replace downloads enqueued during a concurrent first read" do
    download_queue
    entered = Queue.new
    release = Queue.new
    interrupted = T.let(false, T::Boolean)
    # Force a first read to overlap enqueue if the getter creates the hash.
    trace = TracePoint.new(:call, :c_call) do |event|
      next if event.method_id != :let
      next unless event.self.equal?(T)
      next unless Thread.current[:downloads_reader]
      next if interrupted
      next unless caller_locations.any? { |location| location.base_label == "downloads" }

      interrupted = true
      entered << true
      release.pop
    end
    trace.enable
    reader = Thread.new do
      Thread.current[:downloads_reader] = true
      download_queue.downloads
      entered << true
    end
    raise "reader did not start" unless entered.pop(timeout: 2)

    allow(downloadable).to receive(:downloaded_and_valid?).and_return(true)
    download_queue.enqueue(downloadable)
    release << true
    reader.join

    expect(download_queue.downloads).to have_key(downloadable)
  ensure
    trace&.disable
    release&.push(true)
    reader&.join
  end

  it "preserves a pause failure and resumes progress after fetch cleanup" do
    progress = instance_double(Homebrew::DownloadQueue::Progress, resume: nil)
    allow(Homebrew::DownloadQueue::Progress).to receive(:current).and_return(progress)
    allow(progress).to receive(:pause).and_raise("pause failed")

    expect(progress).to receive(:resume)
    expect { download_queue.fetch(only: Resource::BottleManifest) }.to raise_error("pause failed")
  end

  it "resumes progress even when pruning fetched downloads fails" do
    progress = instance_double(Homebrew::DownloadQueue::Progress, pause: nil, resume: nil)
    allow(Homebrew::DownloadQueue::Progress).to receive(:current).and_return(progress)
    allow(download_queue.downloads).to receive(:clear).and_raise("prune failed")

    expect(progress).to receive(:resume)
    expect { download_queue.fetch }.to raise_error("prune failed")
  end

  it "reports rejected download errors in parallel mode and marks the fetch as failed" do
    download_queue.enqueue(downloadable)

    expect { download_queue.fetch }.to output(/network blew up/).to_stderr

    expect(download_queue.failed_downloads).to eq([downloadable])
    expect(Homebrew).to have_failed
  end

  it "defers multi-line failure details on a TTY until the in-place redraw has finished" do
    allow($stdout).to receive(:tty?).and_return(true)
    ENV["TERM"] = "xterm-256color"
    allow(downloadable).to receive(:fetched_size).and_return(nil)
    allow(retryable_download).to receive(:fetch).and_raise(multi_line_download_error)

    download_queue.enqueue(downloadable)

    # Stub the write methods (rather than reassigning $stdout/$stderr) so both
    # streams append to one buffer in call order, the same way they'd interleave
    # on a real terminal.
    combined_output = +""
    allow($stdout).to receive(:print) { |message| combined_output << message }
    allow($stdout).to receive(:flush)
    allow($stderr).to receive(:puts) { |message| combined_output << "#{message}\n" }

    download_queue.fetch

    show_cursor_index = combined_output.index(Tty.show_cursor)
    failure_index = combined_output.index("line one\nline two")

    expect(show_cursor_index).not_to be_nil
    expect(failure_index).not_to be_nil
    # The redraw loop assumes every line it prints in-place occupies exactly one
    # terminal row, so a multi-line failure must be held back until the cursor is
    # restored to normal scrolling, not printed while the redraw is still live.
    expect(failure_index).to be > show_cursor_index
  end

  it "fetches only downloads of the given class and keeps others queued unreported" do
    manifest = instance_double(
      Resource::BottleManifest,
      cached_download:        HOMEBREW_CACHE/"downloads/testball_manifest.json",
      checksum:               nil,
      downloaded_and_valid?:  true,
      downloader:             nil,
      download_queue_message: "Bottle Manifest testball",
      download_queue_name:    "testball",
      download_queue_type:    "Bottle Manifest",
    )
    allow(manifest).to receive(:is_a?) { |klass| klass == Resource::BottleManifest }

    download_queue.enqueue(manifest)
    download_queue.enqueue(downloadable)

    expect do
      download_queue.fetch(only: Resource::BottleManifest)
    end.to output(/Bottle Manifest testball/).to_stderr
    expect(download_queue.downloads.keys).to eq [downloadable]
  end

  it "raises and clears queue state on a bottle manifest failure in parallel mode" do
    allow(retryable_download).to receive(:fetch).and_raise(Resource::BottleManifest::Error.new("manifest missing"))

    download_queue.enqueue(downloadable)

    expect { download_queue.fetch }.to raise_error(Resource::BottleManifest::Error, /manifest missing/)
    expect(download_queue.downloads).to be_empty
  end

  it "reports but tolerates failed downloads when failures are allowed" do
    allow(retryable_download).to receive(:fetch).and_raise(Resource::BottleManifest::Error.new("manifest missing"))

    download_queue.enqueue(downloadable)

    expect { download_queue.fetch(allow_failures: true) }.to output(/✘/).to_stderr
    expect(download_queue.failed_downloads).to be_empty
    expect(Homebrew).not_to have_failed
  end

  it "tolerates failed downloads in serial mode when failures are allowed" do
    allow(Homebrew::EnvConfig).to receive(:download_concurrency).and_return(1)
    allow(retryable_download).to receive(:fetch).and_raise(Resource::BottleManifest::Error.new("manifest missing"))

    download_queue.enqueue(downloadable)

    expect { download_queue.fetch(allow_failures: true) }.to output(/✘/).to_stderr
    expect(Homebrew).not_to have_failed
  end

  it "removes known-bad cached files for checksum mismatch failures" do
    cached_download.dirname.mkpath
    cached_download.write("corrupt")
    allow(retryable_download).to receive(:fetch)
      .and_raise(ChecksumMismatchError.new(cached_download, Checksum.new("aa" * 32), Checksum.new("bb" * 32)))

    download_queue.enqueue(downloadable)

    # The reported checksum comes from the failed verification rather than
    # rehashing the file, which the report itself has already removed.
    expect { download_queue.fetch }
      .to output(/Bottle testball reports different checksum: +#{"aa" * 32}/).to_stderr
      .and output(/checksum of downloaded file: +#{"bb" * 32}/).to_stdout
    expect(download_queue.failed_downloads).to eq([downloadable])
    expect(cached_download).not_to exist
    expect(Homebrew).to have_failed
  end

  it "removes known-bad cached files for checksum mismatch failures in serial mode" do
    allow(Homebrew::EnvConfig).to receive(:download_concurrency).and_return(1)
    cached_download.dirname.mkpath
    cached_download.write("corrupt")
    allow(retryable_download).to receive(:fetch)
      .and_raise(ChecksumMismatchError.new(cached_download, Checksum.new("aa" * 32), Checksum.new("bb" * 32)))

    download_queue.enqueue(downloadable)

    expect { download_queue.fetch }
      .to output(/Bottle testball reports different checksum: +#{"aa" * 32}/).to_stderr
      .and output(/checksum of downloaded file: +#{"bb" * 32}/).to_stdout
    expect(download_queue.failed_downloads).to eq([downloadable])
    expect(cached_download).not_to exist
    expect(Homebrew).to have_failed
  end

  it "removes known-bad cached files for tolerated checksum mismatches" do
    cached_download.dirname.mkpath
    cached_download.write("corrupt")
    allow(retryable_download).to receive(:fetch)
      .and_raise(ChecksumMismatchError.new(cached_download, Checksum.new("aa" * 32), Checksum.new("bb" * 32)))

    download_queue.enqueue(downloadable)

    expect { download_queue.fetch(allow_failures: true) }.to output(/✘/).to_stderr
    expect(cached_download).not_to exist
    expect(Homebrew).not_to have_failed
  end

  it "removes known-bad cached files for tolerated checksum mismatches in serial mode" do
    allow(Homebrew::EnvConfig).to receive(:download_concurrency).and_return(1)
    cached_download.dirname.mkpath
    cached_download.write("corrupt")
    allow(retryable_download).to receive(:fetch)
      .and_raise(ChecksumMismatchError.new(cached_download, Checksum.new("aa" * 32), Checksum.new("bb" * 32)))

    download_queue.enqueue(downloadable)

    expect { download_queue.fetch(allow_failures: true) }.to output(/✘/).to_stderr
    expect(cached_download).not_to exist
    expect(Homebrew).not_to have_failed
  end

  it "removes known-bad cached files for fatal checksum mismatches" do
    cached_download.dirname.mkpath
    cached_download.write("corrupt")
    allow(retryable_download).to receive(:fetch)
      .and_raise(ChecksumMismatchError.new(cached_download, Checksum.new("aa" * 32), Checksum.new("bb" * 32)))

    download_queue.enqueue(downloadable)

    expect { download_queue.fetch }.to output(/different checksum/).to_stderr
    expect(cached_download).not_to exist
    expect(download_queue.failed_downloads).to eq([downloadable])
  end

  it "reports every fatal checksum mismatch when downloads share a cached file" do
    cached_download.dirname.mkpath
    cached_download.write("corrupt")
    shared_downloadable = instance_double(
      Downloadable,
      cached_download:,
      checksum:                        nil,
      downloaded_and_valid?:           false,
      downloader:                      nil,
      download_queue_message:          "API Source testball",
      download_queue_name:             "testball",
      download_queue_type:             "API Source",
      staged_path_from_download_queue: nil,
    )
    allow(retryable_download).to receive(:fetch)
      .and_raise(ChecksumMismatchError.new(cached_download, Checksum.new("aa" * 32), Checksum.new("bb" * 32)))

    download_queue.enqueue(downloadable)
    download_queue.enqueue(shared_downloadable)

    expect { download_queue.fetch }.to output(/different checksum.*different checksum/m).to_stderr
    expect(cached_download).not_to exist
    expect(download_queue.failed_downloads).to contain_exactly(downloadable, shared_downloadable)
  end

  it "removes known-bad cached files for fatal checksum mismatches in serial mode" do
    allow(Homebrew::EnvConfig).to receive(:download_concurrency).and_return(1)
    cached_download.dirname.mkpath
    cached_download.write("corrupt")
    allow(retryable_download).to receive(:fetch)
      .and_raise(ChecksumMismatchError.new(cached_download, Checksum.new("aa" * 32), Checksum.new("bb" * 32)))

    download_queue.enqueue(downloadable)

    expect { download_queue.fetch }.to output(/different checksum/).to_stderr
    expect(cached_download).not_to exist
    expect(download_queue.failed_downloads).to eq([downloadable])
  end

  it "cancels remaining downloads and raises on a bottle manifest failure in serial mode" do
    allow(Homebrew::EnvConfig).to receive(:download_concurrency).and_return(1)
    allow(retryable_download).to receive(:fetch).and_raise(Resource::BottleManifest::Error.new("manifest missing"))

    download_queue.enqueue(downloadable)

    expect(download_queue).to receive(:cancel)
    expect { download_queue.fetch }.to raise_error(Resource::BottleManifest::Error, /manifest missing/)
  end

  it "brackets TTY redraw frames in a DEC 2026 synchronized update" do
    allow($stdout).to receive(:tty?).and_return(true)
    ENV["TERM"] = "xterm-256color"
    allow(downloadable).to receive(:fetched_size).and_return(nil)
    allow(retryable_download).to receive(:fetch).and_return(cached_download)

    # Build the queue while stdout is a TTY so it captures the TTY render path,
    # before the output matcher swaps $stdout to capture the redraw frames.
    download_queue.enqueue(downloadable)

    expect { download_queue.fetch }.to output(
      include("\e[?2026h").and(
        satisfy("closes every synchronized update it opens") do |out|
          last_open = out.rindex("\e[?2026h")
          last_close = out.rindex("\e[?2026l")
          out.scan("\e[?2026h").length <= out.scan("\e[?2026l").length &&
            !last_open.nil? && !last_close.nil? && last_close > last_open
        end,
      ),
    ).to_stdout
  end

  it "does not clear below the frame while the terminal width is unchanged" do
    allow($stdout).to receive(:tty?).and_return(true)
    ENV["TERM"] = "xterm-256color"
    allow(downloadable).to receive(:fetched_size).and_return(nil)
    allow(retryable_download).to receive(:fetch).and_return(cached_download)

    download_queue.enqueue(downloadable)

    expect { download_queue.fetch }.not_to output(include("\e[J")).to_stdout
  end

  context "when the terminal is resized while rendering progress" do
    before { Tty.size_stale! }
    after { Tty.size_stale! }

    it "re-reads the terminal width" do
      allow($stdout).to receive(:tty?).and_return(true)
      ENV["TERM"] = "xterm-256color"
      allow($stdin).to receive(:tty?).and_return(true)
      allow($stdin).to receive(:winsize).and_return([24, 80], [24, 40])
      # Resize while rendering progress rather than in the download thread,
      # which starts as soon as the download is enqueued.
      allow(downloadable).to receive(:fetched_size) do
        Process.kill(:WINCH, Process.pid)
        nil
      end
      allow(retryable_download).to receive(:fetch).and_return(cached_download)
      allow(download_queue).to receive(:stdout_print_and_flush)

      download_queue.enqueue(downloadable)

      expect { download_queue.fetch }.to change(Tty, :width).from(80).to(40)
    end

    it "clears below the frame on the next redraw" do
      allow($stdout).to receive(:tty?).and_return(true)
      ENV["TERM"] = "xterm-256color"
      allow($stdin).to receive(:tty?).and_return(true)
      allow($stdin).to receive(:winsize).and_return([24, 80], [24, 40])
      resized = Queue.new
      allow(downloadable).to receive(:fetched_size) do
        Process.kill(:WINCH, Process.pid)
        resized << true
        nil
      end
      # Keep the download pending until the resize so another frame is drawn.
      allow(retryable_download).to receive(:fetch) do
        resized.pop(timeout: 5)
        cached_download
      end

      download_queue.enqueue(downloadable)

      expect { download_queue.fetch }.to output(include("\e[J")).to_stdout
    end
  end

  it "leaves the final terminal column empty when rendering progress" do
    allow($stdout).to receive(:tty?).and_return(true)
    ENV["TERM"] = "xterm-256color"
    allow(Tty).to receive(:width).and_return(80)
    allow(downloadable).to receive_messages(fetched_size: 559_300_000, total_size: 559_300_000, phase: :downloading)
    allow(retryable_download).to receive(:fetch).and_return(cached_download)

    download_queue.enqueue(downloadable)

    rendered_lines = []
    allow(download_queue).to receive(:stdout_print_and_flush) do |message|
      rendered_lines << message if message.include?("559.3MB")
    end
    download_queue.fetch

    expect(Tty.strip_ansi(rendered_lines.fetch(0)).chomp.each_grapheme_cluster.count).to eq(Tty.width - 1)
  end

  it "emits no synchronized update sequences when stdout is not a TTY" do
    allow($stdout).to receive(:tty?).and_return(false)
    allow(retryable_download).to receive(:fetch).and_return(cached_download)

    download_queue.enqueue(downloadable)

    expect { download_queue.fetch }.not_to output(/\e\[\?2026/).to_stdout
  end

  it "prints the heading to stderr when stdout is not a TTY" do
    allow($stdout).to receive(:tty?).and_return(false)
    allow(retryable_download).to receive(:fetch).and_return(cached_download)
    download_queue.enqueue(downloadable)

    expect { download_queue.fetch(heading: "Downloading Homebrew API data") }
      .to output(/^==> Downloading Homebrew API data$/).to_stderr
  end

  it "keeps the heading off stdout when stdout is not a TTY" do
    allow($stdout).to receive(:tty?).and_return(false)
    allow(retryable_download).to receive(:fetch).and_return(cached_download)
    download_queue.enqueue(downloadable)

    expect { download_queue.fetch(heading: "Downloading Homebrew API data") }
      .not_to output(/Downloading Homebrew API data/).to_stdout
  end

  it "prints the heading to stdout on a TTY" do
    allow($stdout).to receive(:tty?).and_return(true)
    ENV["TERM"] = "xterm-256color"
    allow(downloadable).to receive(:fetched_size).and_return(nil)
    allow(retryable_download).to receive(:fetch).and_return(cached_download)

    # Build the queue while stdout is a TTY so it captures the TTY render path,
    # before the output matcher swaps $stdout to capture the heading.
    download_queue.enqueue(downloadable)

    expect { download_queue.fetch(heading: "Downloading Homebrew API data") }
      .to output(/==>.*Downloading Homebrew API data/).to_stdout
  end

  it "wakes when downloads complete instead of polling with sleep" do
    allow($stdout).to receive(:tty?).and_return(false)
    allow(retryable_download).to receive(:fetch) do
      sleep 0.1
      cached_download
    end

    expect(download_queue).not_to receive(:sleep)

    expect do
      download_queue.enqueue(downloadable)
      download_queue.fetch
    end.to output(/✔︎ Bottle testball/).to_stderr
  end

  it "skips fetching already downloaded files with a valid checksum" do
    cached_download.dirname.mkpath
    cached_download.write("already downloaded")

    allow(downloadable).to receive(:downloaded_and_valid?).and_return(true)

    expect(retryable_download).not_to receive(:fetch)
    expect(downloadable).to receive(:downloader).and_return(nil)

    download_queue.enqueue(downloadable)
    download_queue.fetch
  end

  it "runs queued staging before completing the fetch" do
    allow(retryable_download).to receive(:fetch).and_return(cached_download)

    expect(downloadable).to receive(:stage_from_download_queue?).with(cached_download, pour: false).and_return(true)
    expect(downloadable).to receive(:extracting!).ordered
    expect(downloadable).to receive(:stage_from_download_queue).with(cached_download, pour: false).ordered
    expect(downloadable).to receive(:downloaded!).ordered

    download_queue.enqueue(downloadable, stage: true)
    download_queue.fetch
  end

  it "uses the fetched path for queued staging when it changes during fetch" do
    fetched_download = HOMEBREW_CACHE/"downloads/fetched-testball--0.1.tar.gz"
    allow(retryable_download).to receive(:fetch).and_return(fetched_download)

    expect(downloadable).to receive(:stage_from_download_queue?).with(fetched_download, pour: false).and_return(true)
    expect(downloadable).to receive(:extracting!).ordered
    expect(downloadable).to receive(:stage_from_download_queue).with(fetched_download, pour: false).ordered
    expect(downloadable).to receive(:downloaded!).ordered

    download_queue.enqueue(downloadable, stage: true)
    download_queue.fetch
  end

  it "interrupts queued staging when the fetch is interrupted", timeout: 5 do
    allow(retryable_download).to receive(:fetch).and_return(cached_download)
    allow(downloadable).to receive(:stage_from_download_queue?).and_return(true)
    allow(downloadable).to receive_messages(extracting!: nil, downloaded!: nil)
    fetch_started = Queue.new
    staging_started = Queue.new
    staging_interrupted = Queue.new
    release_fetch = Queue.new
    release_staging = Queue.new
    allow(downloadable).to receive(:download_queue_message) do
      fetch_started << true
      release_fetch.pop
      "Bottle testball"
    end
    allow(downloadable).to receive(:stage_from_download_queue) do
      staging_started << true
      release_staging.pop
    rescue Interrupt
      staging_interrupted << true
      raise
    end

    download_queue.enqueue(downloadable, stage: true)
    fetch_thread = Thread.current
    interrupter = Thread.new do
      next unless staging_started.pop(timeout: 1)
      next unless fetch_started.pop(timeout: 1)

      fetch_thread.raise(Interrupt)
    end

    expect { download_queue.fetch }.to raise_error(Interrupt)
    expect(staging_interrupted.pop(timeout: 1)).to be(true)
  ensure
    release_fetch&.push(true)
    release_staging&.push(true)
    interrupter.kill if interrupter && !interrupter.join(1)
  end

  it "promotes an in-flight download to queued staging" do
    expect(retryable_download).to receive(:fetch).once.and_return(cached_download)
    expect(downloadable).to receive(:stage_from_download_queue?).with(cached_download, pour: false).and_return(true)
    expect(downloadable).to receive(:extracting!).ordered
    expect(downloadable).to receive(:stage_from_download_queue).with(cached_download, pour: false).ordered
    expect(downloadable).to receive(:downloaded!).ordered

    download_queue.enqueue(downloadable)
    download_queue.enqueue(downloadable, stage: true)
    download_queue.fetch
  end

  it "stages duplicate downloads with the same destination once" do
    staged_path = HOMEBREW_TEMP_CELLAR/"testball/0.1"
    bottles = Array.new(2) do
      instance_double(
        Bottle,
        cached_download:,
        downloaded_and_valid?:           false,
        downloader:                      nil,
        download_queue_message:          "Bottle testball",
        download_queue_name:             "testball",
        download_queue_type:             "Bottle",
        staged_path_from_download_queue: staged_path,
      )
    end
    bottles.each do |bottle|
      allow(bottle).to receive_messages(
        downloaded!:                nil,
        extracting!:                nil,
        stage_from_download_queue?: true,
      )
    end
    expect(retryable_download).to receive(:fetch).once.and_return(cached_download)
    expect(bottles.first).to receive(:stage_from_download_queue).once
    expect(bottles.second).not_to receive(:stage_from_download_queue)

    bottles.each { |bottle| download_queue.enqueue(bottle, stage: true) }
    download_queue.fetch
  end

  it "checks attestations for valid cached bottles" do
    bottle = Bottle.allocate
    allow(bottle).to receive_messages(
      cached_download:,
      checksum:               nil,
      downloaded_and_valid?:  true,
      downloader:             nil,
      download_queue_message: "Bottle testball",
      download_queue_name:    "testball",
      download_queue_type:    "Bottle",
    )

    expect(Utils::Attestation).to receive(:check_attestation).with(bottle, quiet: true)

    download_queue.enqueue(bottle, check_attestation: true)
    download_queue.fetch
  end

  describe "Homebrew::DownloadQueue.default", order: :defined do
    it "memoizes the queue created on first use" do
      queue = instance_double(described_class, shutdown: nil)
      allow(described_class).to receive(:new).and_return(queue)

      expect(described_class.default).to be(queue)
    end

    it "does not leak a queue stubbed by an earlier example" do
      expect(described_class.default).to be_an_instance_of(described_class)
    end

    it "shuts down a memoized real queue when reset" do
      queue = described_class.default
      expect(queue).to receive(:shutdown)

      described_class.reset_default
    end
  end
end
