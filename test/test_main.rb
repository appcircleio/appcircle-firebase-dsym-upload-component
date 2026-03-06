# frozen_string_literal: true

# ─── Coverage (must start before loading main.rb) ─────────────────────────────
unless defined?(Coverage) && Coverage.running?
  require 'coverage'
  Coverage.start
end

# ─── Dependencies ─────────────────────────────────────────────────────────────
require 'rspec'
require 'rspec/core/formatters/base_formatter'
require 'open3'
require 'fileutils'
require 'tmpdir'
require 'securerandom'
require 'stringio'

MAIN_RB      = File.expand_path('../main.rb', __dir__)
PROJECT_ROOT = File.dirname(MAIN_RB)

require MAIN_RB

# ─── Custom Formatter ─────────────────────────────────────────────────────────
class ReadableFormatter < RSpec::Core::Formatters::BaseFormatter
  RSpec::Core::Formatters.register(
    self,
    :example_group_started,
    :example_group_finished,
    :example_passed,
    :example_failed,
    :example_pending,
    :dump_summary
  )

  PASS  = "\e[32;1m[ PASS ]\e[0m"
  FAIL  = "\e[31;1m[ FAIL ]\e[0m"
  ERROR = "\e[31;1m[ERROR ]\e[0m"
  SKIP  = "\e[33;1m[ SKIP ]\e[0m"

  DIVIDER     = "\e[90m#{'─' * 72}\e[0m"
  DIVIDER_FAT = "\e[90m#{'═' * 72}\e[0m"

  def initialize(output)
    super
    @depth    = 0
    @failures = []
    @counts   = { passed: 0, failed: 0, pending: 0 }
  end

  # Top-level describe groups cycle through distinct colors
  GROUP_COLORS = [
    "\e[34;1m",  # bold blue
    "\e[35;1m",  # bold magenta
    "\e[36;1m",  # bold cyan
    "\e[33;1m",  # bold yellow
  ].freeze

  def example_group_started(notification)
    group = notification.group
    if group.parent_groups.size <= 1
      output.puts if @depth.zero?
      color = GROUP_COLORS[@depth % GROUP_COLORS.size]
      output.puts "  #{color}#{group.description}\e[0m"
    else
      output.puts "    #{'  ' * (@depth - 1)}\e[90m▸ \e[0m\e[37m#{group.description}\e[0m"
    end
    @depth += 1
  end

  def example_group_finished(_notification)
    @depth -= 1 if @depth > 0
  end

  def example_passed(notification)
    @counts[:passed] += 1
    print_example(PASS, notification.example)
  end

  def example_failed(notification)
    @counts[:failed] += 1
    ex    = notification.example
    exc   = ex.execution_result.exception
    badge = exc.is_a?(RSpec::Expectations::ExpectationNotMetError) ? FAIL : ERROR
    print_example(badge, ex)
    @failures << notification
  end

  def example_pending(notification)
    @counts[:pending] += 1
    ex = notification.example
    output.puts "    #{'  ' * [0, @depth - 1].max}#{SKIP}  #{ex.description}"
  end

  def dump_summary(notification)
    output.puts
    output.puts DIVIDER_FAT

    unless @failures.empty?
      output.puts "\n  \e[1;31mFailures:\e[0m\n"
      @failures.each_with_index do |n, i|
        ex  = n.example
        exc = ex.execution_result.exception
        output.puts "  \e[1m#{i + 1}) #{ex.full_description}\e[0m"
        exc.message.lines.first(6).each do |line|
          output.puts "     \e[31m#{line.rstrip}\e[0m"
        end
        output.puts "     \e[90m# #{ex.location}\e[0m"
        output.puts
      end
      output.puts DIVIDER
    end

    t   = notification.examples.size
    p   = @counts[:passed]
    f   = @counts[:failed]
    s   = @counts[:pending]
    sec = format('%.3fs', notification.duration)

    parts = ["\e[32m#{p} passed\e[0m"]
    parts << "\e[31m#{f} failed\e[0m"  if f > 0
    parts << "\e[33m#{s} pending\e[0m" if s > 0

    overall = f.zero? ? "\e[32;1m✔  All #{t} tests passed\e[0m" : "\e[31;1m✖  #{f} of #{t} tests failed\e[0m"
    output.puts "\n  #{overall}"
    output.puts "  #{parts.join('  |  ')}  \e[90m(#{sec})\e[0m"
    output.puts DIVIDER_FAT
  end

  private

  def print_example(badge, example)
    indent = '  ' * [0, @depth - 1].max
    time   = format('%.3fs', example.execution_result.run_time)
    output.puts "    #{indent}#{badge}  #{example.description}  \e[90m(#{time})\e[0m"
  end
end

# ─── Helpers ──────────────────────────────────────────────────────────────────

# Build a minimal valid .xcarchive structure for find_dsyms tests.
def build_xcarchive(base, dsym_names: ['MyApp.app.dSYM'], app_path: 'Applications/MyApp.app')
  dsyms_dir = File.join(base, 'dSYMs')
  FileUtils.mkdir_p(dsyms_dir)
  dsym_names.each { |n| FileUtils.mkdir_p(File.join(dsyms_dir, n)) }
  plist_content = <<~XML
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
      "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>ApplicationProperties</key>
      <dict>
        <key>ApplicationPath</key>
        <string>#{app_path}</string>
      </dict>
    </dict>
    </plist>
  XML
  File.write(File.join(base, 'Info.plist'), plist_content)
  base
end

# Run main.rb in a subprocess with given ENV hash.
# Unset keys by passing nil as value.
def run_main(env = {})
  clean_env = {
    'AC_ARCHIVE_PATH'              => nil,
    'AC_FIREBASE_EXPORT_ALL'       => nil,
    'AC_FIREBASE_PLIST_PATH'       => nil,
    'AC_REPOSITORY_DIR'            => nil,
    'AC_FIREBASE_CRASHLYTICS_PATH' => nil
  }.merge(env).reject { |_, v| v.nil? }
  Open3.capture3(clean_env, "ruby #{MAIN_RB}")
end

# ─── Tests ────────────────────────────────────────────────────────────────────

RSpec.describe 'Required libraries' do
  %w[English open3 pathname fileutils plist].each do |lib|
    it "loads '#{lib}'" do
      expect { require lib }.not_to raise_error
    end
  end

  it 'makes Open3 available after requiring main.rb' do
    out, _err, status = Open3.capture3("ruby -e \"require '#{MAIN_RB}'; puts Open3.name\"")
    expect(status).to be_success
    expect(out.strip).to eq('Open3')
  end

  it 'makes FileUtils available after requiring main.rb' do
    out, _err, status = Open3.capture3("ruby -e \"require '#{MAIN_RB}'; puts FileUtils.name\"")
    expect(status).to be_success
    expect(out.strip).to eq('FileUtils')
  end

  it 'makes Plist available after requiring main.rb' do
    out, _err, status = Open3.capture3("ruby -e \"require '#{MAIN_RB}'; puts Plist.name\"")
    expect(status).to be_success
    expect(out.strip).to eq('Plist')
  end
end

# ─────────────────────────────────────────────────────────────────────────────

RSpec.describe '#get_env_variable' do
  around do |example|
    old = ENV['_TEST_VAR']
    example.run
    ENV['_TEST_VAR'] = old
  end

  it 'returns the value when the key is set' do
    ENV['_TEST_VAR'] = 'hello'
    expect(get_env_variable('_TEST_VAR')).to eq('hello')
  end

  it 'returns nil when the key is missing' do
    ENV.delete('_TEST_VAR')
    expect(get_env_variable('_TEST_VAR')).to be_nil
  end

  it 'returns nil when the value is an empty string' do
    ENV['_TEST_VAR'] = ''
    expect(get_env_variable('_TEST_VAR')).to be_nil
  end
end

# ─────────────────────────────────────────────────────────────────────────────

RSpec.describe '#run_command' do
  it 'runs a successful command without raising' do
    expect { run_command('echo hi') }.not_to raise_error
  end

  it 'calls abort (SystemExit) when the command exits non-zero' do
    expect { run_command('false') }.to raise_error(SystemExit)
  end
end

# ─────────────────────────────────────────────────────────────────────────────

RSpec.describe '#find_dsyms' do
  let(:tmpdir)    { Dir.mktmpdir('xcarchive_test') }
  let(:dsyms_dir) { File.join(tmpdir, 'dSYMs') }

  before { allow(self).to receive(:run_command) { |cmd| @last_cmd = cmd } }
  after  { FileUtils.rm_rf(tmpdir) }

  context 'when no .dSYM files exist' do
    before { FileUtils.mkdir_p(dsyms_dir) }

    it 'exits with status 1' do
      expect { find_dsyms(tmpdir, false) }.to raise_error(SystemExit)
    end
  end

  context 'when all=true' do
    before { build_xcarchive(tmpdir, dsym_names: ['A.app.dSYM', 'B.app.dSYM']) }

    it 'passes a *.dSYM glob to the zip command' do
      find_dsyms(tmpdir, true)
      expect(@last_cmd).to include('*.dSYM')
    end

    it 'returns a path ending in .zip' do
      expect(find_dsyms(tmpdir, true)).to end_with('.zip')
    end
  end

  context 'when all=false with a valid Info.plist' do
    before { build_xcarchive(tmpdir, dsym_names: ['MyApp.app.dSYM']) }

    it 'zips only the app-specific .dSYM' do
      find_dsyms(tmpdir, false)
      expect(@last_cmd).to include('MyApp.app.dSYM')
      expect(@last_cmd).not_to include('*.dSYM')
    end

    it 'returns a path ending in .zip' do
      expect(find_dsyms(tmpdir, false)).to end_with('.zip')
    end
  end

  context 'when Info.plist is missing' do
    before do
      FileUtils.mkdir_p(dsyms_dir)
      FileUtils.mkdir_p(File.join(dsyms_dir, 'MyApp.app.dSYM'))
    end

    it 'raises RuntimeError mentioning Info.plist' do
      expect { find_dsyms(tmpdir, false) }.to raise_error(RuntimeError, /Info\.plist/)
    end
  end

  context 'when Info.plist is malformed XML' do
    before do
      FileUtils.mkdir_p(dsyms_dir)
      FileUtils.mkdir_p(File.join(dsyms_dir, 'MyApp.app.dSYM'))
      File.write(File.join(tmpdir, 'Info.plist'), 'this is not xml')
    end

    it 'raises RuntimeError about parsing' do
      expect { find_dsyms(tmpdir, false) }.to raise_error(RuntimeError, /Could not parse Info\.plist/)
    end
  end

  context "when Info.plist is missing 'ApplicationProperties'" do
    before do
      FileUtils.mkdir_p(dsyms_dir)
      FileUtils.mkdir_p(File.join(dsyms_dir, 'MyApp.app.dSYM'))
      File.write(File.join(tmpdir, 'Info.plist'), <<~XML)
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict></dict></plist>
      XML
    end

    it 'raises RuntimeError mentioning ApplicationProperties' do
      expect { find_dsyms(tmpdir, false) }.to raise_error(RuntimeError, /ApplicationProperties/)
    end
  end
end

# ─────────────────────────────────────────────────────────────────────────────

RSpec.describe 'ENV validation' do
  let(:tmpdir) { Dir.mktmpdir('env_val_test') }
  after { FileUtils.rm_rf(tmpdir) }

  def touch(path)
    FileUtils.touch(path)
    path
  end

  shared_examples 'a failing validation' do |expected_pattern, env|
    it "fails and stderr matches '#{expected_pattern}'" do
      _out, err, status = run_main(env)
      expect(status.exitstatus).not_to eq(0)
      expect(err).to match(expected_pattern)
    end
  end

  context 'AC_ARCHIVE_PATH is missing' do
    include_examples 'a failing validation', /AC_ARCHIVE_PATH empty/, {}
  end

  context 'AC_ARCHIVE_PATH is empty string' do
    include_examples 'a failing validation',
                     /AC_ARCHIVE_PATH empty/,
                     { 'AC_ARCHIVE_PATH' => '' }
  end

  context 'AC_FIREBASE_PLIST_PATH is missing' do
    include_examples 'a failing validation',
                     /No GoogleService-Info\.plist found/,
                     { 'AC_ARCHIVE_PATH' => '/tmp/fake.xcarchive' }
  end

  context 'AC_REPOSITORY_DIR is missing' do
    include_examples 'a failing validation',
                     /AC_REPOSITORY_DIR empty/,
                     {
                       'AC_ARCHIVE_PATH'        => '/tmp/fake.xcarchive',
                       'AC_FIREBASE_PLIST_PATH' => 'GoogleService-Info.plist'
                     }
  end

  context 'AC_REPOSITORY_DIR is empty string' do
    include_examples 'a failing validation',
                     /AC_REPOSITORY_DIR empty/,
                     {
                       'AC_ARCHIVE_PATH'        => '/tmp/fake.xcarchive',
                       'AC_FIREBASE_PLIST_PATH' => 'GoogleService-Info.plist',
                       'AC_REPOSITORY_DIR'      => ''
                     }
  end

  context 'GoogleService-Info.plist file does not exist on disk' do
    it 'fails with a missing-file error' do
      _out, err, status = run_main(
        'AC_ARCHIVE_PATH'        => '/tmp/fake.xcarchive',
        'AC_FIREBASE_PLIST_PATH' => 'nonexistent.plist',
        'AC_REPOSITORY_DIR'      => tmpdir
      )
      expect(status.exitstatus).not_to eq(0)
      expect(err).to match(/Can not read GoogleService-Info\.plist/)
    end
  end

  context 'AC_FIREBASE_CRASHLYTICS_PATH is missing' do
    it 'fails with a missing upload-symbols error' do
      plist = touch(File.join(tmpdir, 'GoogleService-Info.plist'))
      _out, err, status = run_main(
        'AC_ARCHIVE_PATH'        => '/tmp/fake.xcarchive',
        'AC_FIREBASE_PLIST_PATH' => File.basename(plist),
        'AC_REPOSITORY_DIR'      => tmpdir
      )
      expect(status.exitstatus).not_to eq(0)
      expect(err).to match(/No upload-symbols found/)
    end
  end

  context 'AC_FIREBASE_CRASHLYTICS_PATH points to a non-existent file' do
    it 'fails with a missing upload-symbols error' do
      plist = touch(File.join(tmpdir, 'GoogleService-Info.plist'))
      _out, err, status = run_main(
        'AC_ARCHIVE_PATH'              => '/tmp/fake.xcarchive',
        'AC_FIREBASE_PLIST_PATH'       => File.basename(plist),
        'AC_REPOSITORY_DIR'            => tmpdir,
        'AC_FIREBASE_CRASHLYTICS_PATH' => '/nonexistent/upload-symbols'
      )
      expect(status.exitstatus).not_to eq(0)
      expect(err).to match(/No upload-symbols found/)
    end
  end

  context 'AC_FIREBASE_EXPORT_ALL' do
    let(:plist)    { touch(File.join(tmpdir, 'GoogleService-Info.plist')) }
    let(:crash)    { touch(File.join(tmpdir, 'upload-symbols')) }
    let(:archive)  { Dir.mktmpdir('archive', tmpdir) }
    let(:base_env) do
      {
        'AC_ARCHIVE_PATH'              => archive,
        'AC_FIREBASE_PLIST_PATH'       => File.basename(plist),
        'AC_REPOSITORY_DIR'            => tmpdir,
        'AC_FIREBASE_CRASHLYTICS_PATH' => crash
      }
    end

    it "treats 'YES' as export-all (ENV validation passes, fails at find_dsyms)" do
      out, err, _status = run_main(base_env.merge('AC_FIREBASE_EXPORT_ALL' => 'YES'))
      expect(out + err).to include('No debug symbols were found')
      expect(out + err).not_to match(/AC_FIREBASE_EXPORT_ALL/)
    end

    it "treats any non-YES value as false (ENV validation still passes)" do
      out, err, _status = run_main(base_env.merge('AC_FIREBASE_EXPORT_ALL' => 'NO'))
      expect(out + err).to include('No debug symbols were found')
      expect(out + err).not_to match(/AC_FIREBASE_EXPORT_ALL/)
    end

    it 'treats a missing value as false (ENV validation still passes)' do
      out, err, _status = run_main(base_env)
      expect(out + err).to include('No debug symbols were found')
      expect(out + err).not_to match(/AC_FIREBASE_EXPORT_ALL/)
    end
  end
end

# ─── Coverage Report ──────────────────────────────────────────────────────────
def print_coverage_report
  return unless defined?(Coverage) && Coverage.running?

  result = begin
    Coverage.result(stop: false, clear: false)
  rescue ArgumentError
    Coverage.result
  end

  main_path = result.keys.find { |p| p&.end_with?('main.rb') }
  return puts("\nCoverage: main.rb not found in results") unless main_path

  data      = result[main_path]
  lines     = data.each_with_index.reject { |c, _| c.nil? }
  total     = lines.size
  covered   = lines.count { |c, _| c.to_i > 0 }
  pct       = total.positive? ? (covered * 100.0 / total).round(1) : 100.0
  uncovered = lines.select { |c, _| c.to_i == 0 }.map { |_, i| i + 1 }

  color = pct == 100 ? "\e[32;1m" : pct >= 80 ? "\e[33m" : "\e[31m"
  bar_filled = (pct / 5).round
  bar = "\e[32m" + '█' * bar_filled + "\e[90m" + '░' * (20 - bar_filled) + "\e[0m"

  puts "\n\e[90m#{'═' * 72}\e[0m"
  puts '  Coverage Report'
  puts "\e[90m#{'─' * 72}\e[0m"
  puts "  main.rb  #{bar}  #{color}#{pct}%\e[0m  (#{covered}/#{total} lines)"
  if uncovered.any? && uncovered.size <= 20
    puts "  Uncovered lines: \e[90m#{uncovered.join(', ')}\e[0m"
  elsif uncovered.any?
    puts "  Uncovered lines: \e[90m#{uncovered.first(15).join(', ')} … (+#{uncovered.size - 15} more)\e[0m"
  end
  puts "\e[90m#{'═' * 72}\e[0m"
end

# ─── Runner ───────────────────────────────────────────────────────────────────
if __FILE__ == $PROGRAM_NAME
  RSpec.configure do |config|
    config.add_formatter ReadableFormatter
    config.color        = true
    config.order        = :defined
  end

  exit_code = RSpec::Core::Runner.run(['--order', 'defined'])
  print_coverage_report
  exit exit_code
end
