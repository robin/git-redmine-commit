$:.unshift(File.dirname(__FILE__)) unless
  $:.include?(File.dirname(__FILE__)) || $:.include?(File.expand_path(File.dirname(__FILE__)))

require 'fileutils'
require 'tempfile'
require 'yaml'
require 'open-uri'
require 'optparse'
require 'ostruct'

require 'rubygems'
require 'xmlsimple'

class GitRedmineCommit  
  defaults = {}
  REDMINECOMMIT_RC = File.join("#{ENV['HOME']}",".redmine_commit_rc")
  GRC_CONFIG = if File.exist?(REDMINECOMMIT_RC)
            defaults.merge(YAML.load_file(REDMINECOMMIT_RC))
          else
            defaults
          end
  
  def initialize(args)
    @options = {}
    
    opts = OptionParser.new do |opts|
      opts.banner = "Usage: #{File.basename($0)} issue_id [options] -- [git-commit options]"
      opts.separator ""
      opts.separator "Specify the api key and url. You only need to do it once for each repo."
      
      opts.on( "--redmine-api-key [key]", String,
               "The api access key to access redmine." ) do |opt|
        @options[:key] = opt
      end
      opts.on( "--redmine-url [url]", String,
               "URL of your redmine." ) do |opt|
        @options[:url] = opt
      end
      opts.separator ""
      opts.on("-h", "--help", "Displays this help info") do
        puts opts
        exit 0
      end

      opts.separator ""
      opts.separator "Example:"
      opts.separator "\t#{File.basename($0)} 3125 -- -a"
    end
    
    opts.parse!(args)
    
    if args.empty?
      puts "Please specify the redmine issue id"
      puts opts
      exit 1
    end
    
    @options[:issue_id] = args.shift.to_i
    @options[:git_options] = args.join(' ')
    @options[:repo] = `git config --get remote.origin.url`.chomp
    @options[:repo] = Dir.pwd if @options[:repo].empty?
  end
  
  def set_redmine_config(redmine_url, api_key, repo)
    GRC_CONFIG[redmine_url] ||= {}
    GRC_CONFIG[redmine_url][:key] = api_key
    GRC_CONFIG[redmine_url][:repos] ||= []
    GRC_CONFIG[redmine_url][:repos] << repo
    GRC_CONFIG[redmine_url][:repos].uniq!
    
    File.open( REDMINECOMMIT_RC, 'w' ) do |out|
        YAML.dump( GRC_CONFIG, out )
    end    
  end
  
  def run
    git_repo = @options[:repo]
    unless @options[:key] && @options[:url]
      config = get_config(git_repo) || get_config(Dir.pwd) || set_config(git_repo)
      @options[:key] ||= config[:key]
      @options[:url] ||= config[:url]
    end
    set_redmine_config(@options[:url], @options[:key], @options[:repo])
    
    url = File.join(@options[:url], "issues", "#{@options[:issue_id]}.xml?key=#{@options[:key]}")
    issue = open(url) { |f| XmlSimple.xml_in(f)}
    title = "fix issue ##{issue['id']} : #{issue['subject']}" 
    temp = Tempfile.new('redmine_commit')
    temp << title
    temp.close
    puts `git commit #{@options[:git_options]} -F #{temp.path}`
  end

  def get_config(git_repo)
    redmine_url = GRC_CONFIG.keys.select {|k| 
      rslt = false
      GRC_CONFIG[k][:repos].each {|repo|
        rslt = true and break if git_repo == repo
      }
      rslt
    }[0]
    
    {:url => redmine_url, :key => GRC_CONFIG[redmine_url][:key]} if redmine_url
  end
  
  def set_config(git_repo)
    redmine_url = @options[:url]
    until redmine_url && !redmine_url.empty?
      print "Redmine url: "
      redmine_url = STDIN.gets.chomp
    end
    
    GRC_CONFIG[redmine_url] ||= {}

    api_key = @options[:key] || GRC_CONFIG[redmine_url][:key]
    until api_key && !api_key.empty?
      print "Redmine api key: "
      api_key =  STDIN.gets.chomp
    end
    {:url => redmine_url, :key => api_key}
  end
end