#!/usr/bin/env ruby

module PubAnnotationAccessor; end unless defined? PubAnnotationAccessor

class PubAnnotationAccessor::ChemdnerAnnotations
  attr_reader :titles, :abstracts

  def initialize (plain_abstracts, plain_annotations)
    titles, abstracts = read_text(plain_abstracts)

    ## read annotations into titles and abstracts
    titles.each_value{|v| v[:denotations] = []}
    abstracts.each_value{|v| v[:denotations] = []}

    plain_annotations.each_line do |line|
      pmid, ta, b, e, text, label = line.chomp.split("\t")
      if ta == 'T'
        titles[pmid][:denotations] << {:span => {:begin => b, :end => e}, :obj => label}
      elsif ta == 'A'
        abstracts[pmid][:denotations] << {:span => {:begin => b, :end => e}, :obj => label}
      else
        raise ArgumentError, "something wrong"
      end
    end

    @titles = titles.values
    @abstracts = abstracts.values
  end

  def read_text(plain_abstracts)
    titles, abstracts = {}, {}

    plain_abstracts.each_line do |line|

      pmid, title, abstract = line.chomp.split("\t")
      titles[pmid] = {sourcedb:'PubMed', sourceid:pmid, text: title}
      abstracts[pmid] = {sourcedb:'PubMed', sourceid:pmid, text: abstract}
    end

    [titles, abstracts]
  end
end


if __FILE__ == $0
  require 'json'

  odir = 'json'

  ## command line option processing
  require 'optparse'
  optparse = OptionParser.new do|opts|
    opts.banner = "Usage: pubannotation_accessor.rb [options]"

    opts.on('-o', '--output directory', "specifies the output directory. (default: #{odir})") do |d|
      odir = d
      odir.sub(%r|/$|, '')
    end

    opts.on('-h', '--help', 'displays this screen') do
      puts opts
      exit
    end
  end

  optparse.parse!

  if odir != '/' && !File.exists?(odir)
    Dir.mkdir(odir)
    warn "The output directory, '#{odir}', is created."
  end

  warn "The output is stored in the directory, '#{odir}'."

  ## read files
  plain_abstracts   = File.read(ARGV[0])
  plain_annotations = File.read(ARGV[1])

  ## parsing
  annotations = PubAnnotationAccessor::ChemdnerAnnotations.new(plain_abstracts, plain_annotations)

  annotations.titles.each do |a|
    outfilename = "#{a[:sourcedb]}-#{a[:sourceid]}-title.json"
    File.open(odir + '/' + outfilename, 'w') {|f| f.write(a.to_json)}
  end

  annotations.abstracts.each do |a|
    outfilename = "#{a[:sourcedb]}-#{a[:sourceid]}-abstract.json"
    File.open(odir + '/' + outfilename, 'w') {|f| f.write(a.to_json)}
  end
end
