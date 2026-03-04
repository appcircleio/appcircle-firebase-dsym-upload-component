# frozen_string_literal: true

require 'English'
require 'os'
require 'pathname'
require 'fileutils'
require 'plist'
require 'open3'

def get_env_variable(key)
  ENV[key].nil? || ENV[key] == '' ? nil : ENV[key]
end

def run_command(cmd)
  puts "@@[command] #{cmd}"
    status = nil
    stdout_str = nil
    stderr_str = nil
    Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
        stdout.each_line do |line|
            puts line
        end
        stdout_str = stdout.read
        stderr_str = stderr.read
        status = wait_thr.value
    end
  
    unless status.success?
        abort(stderr_str)
    end
end

def find_dsyms(path, all)
  dsymfiles = Dir.glob("#{path}/dSYMs/*.dSYM")
  if dsymfiles.count.zero?
    puts 'No debug symbols were found. Please check, Build.xcarchive file is available or not.'
    exit 1
  end

  filename = File.join("#{File.basename(path, '.*')}.app.dSYM.zip")
  dsym_folder_path = File.expand_path(File.join(path, 'dSYMs'))
  zipped_dsym_path = File.expand_path(filename)
  puts "Zipping dSYM files from #{dsym_folder_path} to #{zipped_dsym_path}"

  if all
    cmd = "cd \"#{dsym_folder_path}\" && zip -r \"#{zipped_dsym_path}\" \"#{dsym_folder_path}\"/*.dSYM"
  else
    plist = Plist.parse_xml(File.join(path, 'Info.plist'))
    app_name = File.basename(plist['ApplicationProperties']['ApplicationPath'])
    dsym_name = "#{app_name}.dSYM"
    cmd = "cd \"#{dsym_folder_path}\" && zip -r \"#{zipped_dsym_path}\" \"#{dsym_name}\""
  end
  run_command(cmd)
  zipped_dsym_path
end

archive_path = get_env_variable('AC_ARCHIVE_PATH')
raise 'AC_ARCHIVE_PATH empty' if archive_path.nil? 
export_all = get_env_variable('AC_FIREBASE_EXPORT_ALL') == 'YES'
google_plist = get_env_variable('AC_FIREBASE_PLIST_PATH')
raise 'No GoogleService-Info.plist found' if google_plist.nil?
repository_path =  get_env_variable('AC_REPOSITORY_DIR')
google_plist = File.join(repository_path, google_plist)
raise "Can not read GoogleService-Info.plist at #{google_plist}" if !File.file?(google_plist)
crashlytics_path = get_env_variable('AC_FIREBASE_CRASHLYTICS_PATH')
raise "No upload-symbols found at #{crashlytics_path}" if crashlytics_path.nil? || !File.file?(crashlytics_path)

zipped_dsym_path = find_dsyms(archive_path, export_all)
cmd = "\"#{crashlytics_path}\" -gsp \"#{google_plist}\" -p ios \"#{zipped_dsym_path}\""
result = run_command(cmd)
puts result
