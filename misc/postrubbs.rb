#!/usr/bin/env ruby
#
# postrubbs: posting to RuBBS via e-mail. $Revision: 1.11 $
#
# version 1.0.3 2001.11.23 by TADA Tadashi <sho@spc.gr.jp>
#    trimming Subject treatment more.
# version 1.0.2 2001.11.21 by TADA Tadashi <sho@spc.gr.jp>
#    trimming From treatment.
#    trimming Subject treatment more.
#    don't show e-mail address in default.
# version 1.0.1 2001.11.19 by TADA Tadashi <sho@spc.gr.jp>
#    trimming Subject treatment.
# version 1.0.0 2001.11.17 by TADA Tadashi <sho@spc.gr.jp>
#
# Copyright (C) 2001, All right reserved by TADA Tadashi <sho@spc.gr.jp>
# You can redistribute it and/or modify it under GPL2.
#
POSTRUBBS_VERSION = '1.0.2'

def usage
	puts "postrubbs: posting to RuBBS via e-mail, version #{POSTRUBBS_VERSION}"
	puts "usage: postrubbs <URL>"
	exit
end

if ARGV.length < 1 then
	usage
end
url = ARGV.shift
if %r|http://([^:/]*):?(\d*)(/.*)| =~ url then
	host = $1
	port = $2.to_i
	cgi = $3
	if not host or not cgi then
		usage
	end
	port = 80 if port == 0
else
	usage
end


require 'net/http'
require 'cgi'
require 'nkf'

mail = NKF::nkf( '-e', $stdin.read )
header = true
headers = {}
body = ''
current = nil
mail.each do |s|
	s.chomp!
	if header and s.length == 0 then
		header = false
		next
	end
	if header then
		case s
		when /^\s+(.*)/
			headers[current] = headers[current] + $1 if current
		when /^(.*?):\s*(.*)/
			current = $1.downcase
			headers[current] = $2
		end
	else
		body << s + "\n"
	end
end

if /text\/plain/i !~ headers['content-type'] then
	$stderr.puts 'postrubbs: only can post text message.'
	exit
end

name = nil
mail = nil
if /(.*?)\s*<(.*)>/ =~ headers['from'] then
	mail = $2
	name = $1.sub( /^"/, '' ).sub( /"$/, '' )
elsif /(.*?)\s*\(.*\)/ =~ headers['from']
	name = $2
	mail = $1
elsif %r|[0-9a-zA-Z_.-]+@[\(\)%!0-9a-zA-Z_$@.&+-,'"*-]+| =~ headers['from']
	mail = $&
else
	name = headers['from']
end
name = mail.sub( /@.*$/, '' ) if not name and mail
name = 'anonymous' if not name
mail = '' # until mail # if you want to show e-mail address, remove this comment mark.
puts "name[#{name}]" if $DEBUG
puts "mail[#{mail}]" if $DEBUG

subject = headers['subject'] || 'Re: Re: no subject'
orig_subj = subject.dup
subject.sub!( /^(re(\[\d+\])?:\s*)+/i, '' )
subject.sub!( /^\([^:]*?:\d+\)\s*/i, '' )
subject.sub!( /^(re(\[\d+\])?:\s*)+/i, '' )
subject = 'Re: ' + subject if /^re:\s*/i =~ orig_subj
puts "subj[#{subject}]" if $DEBUG

reply_to = nil
if /<.*?\.(\d+)@.*>/ =~ headers['in-reply-to'] then
	reply_to = $1
elsif /<[^<>]+?\.(\d+)@[^<>]+>$/ =~ headers['references']
	reply_to = $1
end
puts "repl[#{reply_to}]" if $DEBUG

data = "action=append"
data += "&name=#{CGI::escape name}"
data += "&mail=#{CGI::escape mail}"
data += "&reply_to=#{CGI::escape reply_to}" if reply_to
data += "&subject=#{CGI::escape subject}"
data += "&contents=#{CGI::escape body}"
p data

begin
	puts "host[#{host}]" if $DEBUG
	puts "port[#{port}]" if $DEBUG
	puts "cgi [#{cgi}]" if $DEBUG
	Net::HTTP.start( host, port ) do |http|
		res, = http.post( cgi, data )
	end
rescue Net::ProtoRetriableError
rescue
	$stderr.puts "postrubbs: #{$!}"
end

