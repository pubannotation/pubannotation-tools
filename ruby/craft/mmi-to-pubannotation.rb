#!/usr/bin/env ruby

module PubAnnotationAccessor
  def PubAnnotationAccessor.loadMMI (txt, mmi)
    entries = txt.split(/\n\n/)

    texts = {}
    offsets = {}
    entries.each do |e|
      buffer = ''
      offset = nil
      pmid = nil
      tiab = nil

      e.each_line do |l|
        if l[0,5] == 'PMID-'
          pmid = l[6..-1]
          pmid.chomp!
        end

        if l[0,5] == 'TI  -'
          offsets[pmid] = buffer.length - 1
          tiab = l
        end
        buffer += l

        if l[0,5] == 'AB  -' or l[0,5] == 'PG  -' or l[0,5] == '     ' 
          tiab += l
        end

        if l[0,5] == 'FAU -'
          texts[pmid] = tiab
        end

      end
    end

    annotations = []

    prev_pmid = ''
    denotations = []
    num = 0

    mmi.each_line do |l|
      fs = l.split('|')
      pmid      = fs[0]
      mm        = fs[1]
      score     = fs[2]
      name      = fs[3]
      cui       = fs[4]
      semtype   = fs[5]
      trigger   = fs[6]
      location  = fs[7]
      positions = fs[8..-2]

      if pmid != prev_pmid
        unless denotations.empty?
          annotations << {:sourcedb => 'PubMed', :sourceid => prev_pmid, :text => texts[prev_pmid], :denotations => denotations}
        end

        denotations = []
        num = 0
      end

      if mm == 'MM'
        # cleaning
        positions = [positions] unless positions.respond_to?(:each)

        positions.each do |p|
          if (p =~ %r|^([1-9][0-9]*):([1-9][0-9]*)$|)
            offbeg = $1.to_i - offsets[pmid]
            offend = $2.to_i + offbeg
            num += 1
            denotations << {id:'T' + num.to_s, span:{:begin => offbeg, :end => offend}, obj:cui}
          else
            # warn l
          end
        end
      end

      prev_pmid = pmid
    end

    annotations
  end
end


if __FILE__ == $0
  require 'rest_client'
  require 'json'
  require 'highline/import'
  require 'logger'

  hosturl = nil
  odir = nil
  logger = nil

  ## config file processing
  if File.exists?('./mmi-to-pubann.cfg')
    require 'parseconfig'
    config   = ParseConfig.new('./mmi-to-pubann.cfg')
    hosturl  = config['hostURL']
    username = config['username']
    password = config['password']
    project  = config['project']
  end


  ## command line option processing
  require 'optparse'
  optparse = OptionParser.new do|opts|
    opts.banner = "Usage: pubannotation_accessor.rb [options]"

    opts.on('-o', '--output directory', "specifies the output directory.") do |d|
      odir = d
      odir.sub(%r|/+|, '')
    end

    opts.on('-l', '--location URL', "specifies the URL of the host.") do |u|
      hosturl = u
    end

    opts.on('-p', '--project name', 'specifies the user name.') do |p|
      project = p
    end

    opts.on('-u', '--user name', 'specifies the user name.') do |n|
      username = n
    end

    opts.on('-h', '--help', 'displays this screen') do
      puts opts
      exit
    end
  end

  optparse.parse!

  if odir
    if File.exists?(odir)
      puts "The output is stored in the directory, '#{odir}'."
    else
      Dir.mkdir(odir)
      puts "The output directory, '#{odir}', is created."
    end
  elsif hosturl
    puts "host URL : #{hosturl}"
    puts "project  : #{project}"
    if username
      puts "userename: #{username}" 
    else
      username = ask("username: ") unless username
    end
    password = ask("password : ") {|q| q.echo = '*'} unless password

    abort "You must supply your username and passoword." if username == nil or username.empty? or password == nil or password.empty?

    pubann_resource = RestClient::Resource.new(hosturl, {:user => username, :password => password, :headers => {:content_type => :json, :accept => :json}})
    # pubann_resource = RestClient::Resource.new(hosturl, :headers => {:content_type => :json, :accept => :json})
  end


  puts "#{ARGV[0]}, #{ARGV[1]}"

  ## read files
  txt = File.read(ARGV[0])
  mmi = File.read(ARGV[1])

  ## parsing
  annotations = PubAnnotationAccessor.loadMMI(txt, mmi)

  annotations.each do |a|
    if (odir)
      outfilename = "#{a[:sourcedb]}-#{a[:sourceid]}-TIAB.json"
      # puts outfilename
      File.open(odir + '/' + outfilename, 'w') {|f| f.write(a.to_json)}

    elsif (hosturl)
      doc_path =  "/projects/#{project}/docs/project_docs"
      pubann_resource[doc_path].post({:sourcedb => 'PubMed', :ids => a[:sourceid]}.to_json) do |response, request, result|
        case response.code
        when 200 .. 299 then puts 'document checked'
        else 
          unless logger
            logger = Logger.new File.new('mmi-to-pubann.log', 'w')
            logger.level = Logger::WARN
          end
          logger.warn "document check failure: #{a[:sourceid]}."
          warn "document check failure: #{a[:sourceid]}"
          next
        end
      end

      post_path = "/projects/#{project}/docs/sourcedb/#{a[:sourcedb]}/sourceid/#{a[:sourceid]}/annotations.json"
      puts "post annotation to #{post_path}"
      pubann_resource[post_path].post(a.to_json) do |response, request, result|
        case response.code
        when 200 .. 299 then puts 'post succeeded'
        else
          unless logger
            logger = Logger.new File.new('mmi-to-pubann.log', 'w')
            logger.level = Logger::WARN
          end
          logger.warn "post failure: #{a[:sourceid]}."
          warn "post failure: #{a[:sourceid]}"
        end
      end
    end

  end
end
