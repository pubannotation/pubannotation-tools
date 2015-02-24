#!/usr/bin/env ruby
require 'nokogiri'

module PubAnnotationAccessor
  def PubAnnotationAccessor.id_conversion (id)
    idp = id.split('.')
    "#{idp[3]}-#{idp[1]}-#{idp[2]}"
  end

  def PubAnnotationAccessor.loadSemRep (xml)
    doc = Nokogiri::XML.parse(xml)

    text = ''
    denotations = []
    relations = []
    pnum = 0
    rnum = 0
    doc.xpath('//SemRepAnnotation/Document/Utterance').each do |u|
      text += "\n" unless text.empty?
      offset = text.length
      text += u.attr("text")

      u.xpath('.//Entity').each do |e|
        id      = PubAnnotationAccessor.id_conversion(e.attr("id"))

        cui    = e.attr("cui")
        name   = e.attr("name")

        tbegin = e.attr("begin").to_i + offset - 1
        tend   = e.attr("end").to_i + offset

        unless cui
          warn "CUI does not exist: #{e.attr("id")}"
          next
        end

        denotations << {:id => id, :begin => tbegin, :end => tend, :obj => cui}
      end

      u.xpath('.//Predication').each do |r|
        s      = r.xpath('.//Subject')
        p      = r.xpath('.//Predicate')
        o      = r.xpath('.//Object')

        pnum += 1
        pid    = 'T' + pnum.to_s
        pbegin = p.attr("begin").value().to_i + offset - 1
        pend   = p.attr("end").value().to_i + offset
        ptype  = p.attr("type")

        denotations << {:id => pid, :begin => pbegin, :end => pend, :obj => ptype}

        sid    = PubAnnotationAccessor.id_conversion(s.attr("entityID").value())
        oid    = PubAnnotationAccessor.id_conversion(o.attr("entityID").value())

        rnum += 1
        rid    = 'R' + rnum.to_s
        relations << {:id => rid, :subj => sid, :pred => 'subjectOf', :obj => pid }

        rnum += 1
        rid    = 'R' + rnum.to_s
        relations << {:id => rid, :subj => oid, :pred => 'objectOf', :obj => pid }
      end
    end

    {:text => text, :denotations => denotations, :relations => relations}
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
  if File.exists?('./semrep-to-pubann.cfg')
    require 'parseconfig'
    config   = ParseConfig.new('./semrep-to-pubann.cfg')
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


  ARGV.each do |f|
    filebase = File.basename(f, "xml")
    pmid = filebase.split('-')[1]
    puts filebase

    ## read files
    xml = File.read(f)

    ## parsing
    annotations = PubAnnotationAccessor.loadSemRep(xml)

    if (odir)
      outfilename = "PubMed-#{pmid}-TIAB.json"
      # puts outfilename
      File.open(odir + '/' + outfilename, 'w') {|f| f.write(annotations.to_json)}

    elsif (hosturl)
      doc_path =  "/projects/#{project}/docs/project_docs"
      pubann_resource[doc_path].post({:sourcedb => 'PubMed', :ids => pmid}.to_json) do |response, request, result|
        case response.code
        when 200 .. 299 then puts 'document checked'
        else 
          unless logger
            logger = Logger.new File.new('semrep-to-pubann.log', 'w')
            logger.level = Logger::WARN
          end
          logger.warn "document check failure: #{pmid}."
          warn "document check failure: #{pmid}"
          next
        end
      end

      post_path = "/projects/#{project}/docs/sourcedb/PubMed/sourceid/#{pmid}/annotations.json"
      puts "post annotation to #{post_path}"
      pubann_resource[post_path].post(annotations.to_json) do |response, request, result|
        case response.code
        when 200 .. 299 then puts 'post succeeded'
        else
          unless logger
            logger = Logger.new File.new('semrep-to-pubann.log', 'w')
            logger.level = Logger::WARN
          end
          logger.warn "post failure: #{pmid}."
          warn "post failure: #{pmid}"
        end
      end
    end
  end
end
