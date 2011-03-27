require "rake"
require "fileutils"
require "pp"
require "erb"
require "rexml/document"

begin
  require 'ant'
rescue LoadError
  abort 'This Rakefile requires JRuby. Please use jruby -S rake.'
end

require "mirah"

module Pindah
  VERSION = '0.5.0'

  def self.infer_sdk_location(path)
    tools = path.split(":").detect {|p| File.exists? "#{p}/android" }
    File.expand_path("#{tools}/..")
  end

  DEFAULTS = { :output => File.expand_path("bin"),
    :src => File.expand_path("src"),
    :classpath => Dir["jars/*jar"],
    :sdk => Pindah.infer_sdk_location(ENV["PATH"])
  }

  TARGETS = { "1.5" => 3, "1.6" => 4,
    "2.1" => 7, "2.2" => 8, "2.3" => 9 }

  ANT_TASKS = ["clean", "javac", "compile", "debug", "release",
               "install", "uninstall"]

  task :generate_manifest # TODO: generate from yaml?

  desc "Tail logs from a device or a device or emulator"
  task :logcat do
    system "adb logcat #{@spec[:log_spec]}"
  end

  desc "Print the project spec"
  task :spec do
    pp @spec
  end

  desc "Run the project debug .apk on a device or emulator"
  task :run => [:install] do
    manifest_xml = REXML::Document.new(File.new("AndroidManifest.xml"))
    package_name = manifest_xml.root.attributes["package"]
    main_activity = REXML::XPath.first(manifest_xml, "//application/activity[intent-filter[action[@android:name='android.intent.action.MAIN']]]/attribute::android:name").value
    system "adb shell 'am start -a android.intent.action.MAIN -n #{package_name}/#{package_name}.#{main_activity}'"
  end

  task :default => [:install]

  def self.spec=(spec)
    abort "Must provide :target_version in Pindah.spec!" if !spec[:target_version]
    abort "Must provide :name in Pindah.spec!" if !spec[:name]

    @spec = DEFAULTS.merge(spec)

    @spec[:root] = File.expand_path "."
    @spec[:target] ||= TARGETS[@spec[:target_version].to_s.sub(/android-/, '')]
    @spec[:classes] ||= "#{@spec[:output]}/classes/"
    @spec[:classpath] << @spec[:classes]
    @spec[:classpath] << "#{@spec[:sdk]}/platforms/android-#{@spec[:target]}/android.jar"
    @spec[:log_spec] ||= "ActivityManager:I #{@spec[:name]}:D " +
      "AndroidRuntime:E *:S"

    ant_setup
  end

  def self.ant_setup
    @ant = Ant.new

    # TODO: this is lame, but ant interpolation doesn't work for project name
    build_template = ERB.new(File.read(File.join(File.dirname(__FILE__), '..',
                                                 'templates', 'build.xml')))
    build = "/tmp/pindah-#{Process.pid}-build.xml"
    File.open(build, "w") { |f| f.puts build_template.result(binding) }
    at_exit { File.delete build }

    # TODO: add key signing config
    { "target" => "android-#{@spec[:target]}",
      "target-version" => "android-#{@spec[:target_version]}",
      "src" => @spec[:src],
      "sdk.dir" => @spec[:sdk],
      "classes" => @spec[:classes],
      "classpath" => @spec[:classpath].join(Java::JavaLang::System::
                                            getProperty("path.separator"))
    }.each do |key, value|
      @ant.project.set_user_property(key, value)
    end

    Ant::ProjectHelper.configure_project(@ant.project, java.io.File.new(build))

    # Turn ant tasks into rake tasks
    ANT_TASKS.each do |name, description|
      desc @ant.project.targets[name].description
      task(name) { @ant.project.execute_target(name) }
    end
  end
end
