#!/usr/bin/env ruby
#
# squeeze: make (mail) text files from RuBBS's database. $Revision: 1.6 $
#
# Copyright (C) 2001, All right reserved by TADA Tadashi <sho@spc.gr.jp>
# You can redistribute it and/or modify it under GPL2.
#

RUBBS_SQUEEZE_VERSION = '1.0.5'

=begin ChangeLog
2002-04-25 by TADA Tadashi <sho@spc.gr.jp>
	* 1.0.5.
	* --dummy option.

2002-04-23 by TADA Tadashi <sho@spc.gr.jp>
	* 1.0.4.
	* --all option.
   
2001-12-28 by TADA Tadashi <sho@spc.gr.jp>
	* 1.0.3.
	* fix bug: @encoding -> encoding.

2001-11-16 by TADA Tadashi <sho@spc.gr.jp>
	* 1.0.2.
	* --path option.

2001-09-13 by TADA Tadashi <sho@spc.gr.jp>
	* 1.0.1.
	* for empty date.
	* In-Reply-To support.

2001-09-05 by TADA Tadashi <sho@spc.gr.jp>
	* 1.0.0.
=end

def usage
	puts <<-USAGE
squeeze: making text files from RuBBS's database.
usage: squeeze [-ad] [-p <RuBBS path>] <BBS name> <dest path>
    --all,   -a: squeeze all articles also hidden.
    --dummy, -d: make dummy file when article was removed. use with --all.
    --path,  -p: path of rubbs.rb.
	USAGE
	exit
end

require 'getoptlong'
parser = GetoptLong::new
all = false
dummy = false
rubbs_path = nil
parser.set_options(
	['--all', '-a', GetoptLong::NO_ARGUMENT],
	['--dummy', '-d', GetoptLong::NO_ARGUMENT],
	['--path', '-p', GetoptLong::REQUIRED_ARGUMENT]
)
begin
	parser.each do |opt, arg|
		case opt
		when '--all'
			all = true
		when '--dummy'
			dummy = true
		when '--path'
			rubbs_path = arg
		end
	end
rescue
	usage
end
src = ARGV.shift
dest = ARGV.shift
usage if not src or not dest
dest = File::expand_path( dest )
dest += '/' if /\/$/ !~ dest
Dir::chdir( rubbs_path ) if rubbs_path

require 'rubbs'
require 'socket'

def make_text( bbs, serial, article, dummy = false )
	@name = bbs
	if dummy and not article.alive? then
		name = ''
		subject = ''
		mail = reply = 'anonymous@unknown'
		contents = 'text was removed.'
	else
		name = article.name
		subject = article.subject
		mail = reply = article.mail.length == 0 ? 'anonymous@unknown' : article.mail
		contents = article.contents
	end
	
	if article.date.empty? then
		now = Time::at( 0 )
	else
		ye, mo, da, ho, mi, se, tz = article.date.split( /[\/ :]/ )
		now = Time::local( ye, mo, da, ho, mi, se )
	end
	date = now.strftime( "%a, %d %b %Y %X #{tz}" )
	message_id = "<#{bbs}.#{serial}@#{Socket::gethostname.sub(/^.+?\./,'')}>"
	if /^ja/ =~ @lang then
		encoding = 'ISO-2022-JP'
	else
		encoding = @encoding
	end
	@reply_to = article.reply_to
	if not @reply_to.empty?
		@in_reply_to = "<#{bbs}.#{@reply_to}@#{Socket::gethostname.sub(/^.+?\./,'')}>"
	end

	text = ERbLight::new( File::readlines( 'conf/mail.rtxt' ).join ).result( binding )
end

db = DBClass.open( "#{src}#{DB_SUFFIX}" )
	(1...(db['latest'].to_i)).each do |serial|
		a = Article::decode( db[serial.to_s] )
		if all or a.alive? then
			next if FileTest.exist?( "#{dest}#{serial}" )
			File::open( "#{dest}#{serial}", 'w' ) do |o|
				o.write make_text( src, serial, a, dummy )
			end
		elsif FileTest.exist?( "#{dest}#{serial}" )
			File::delete( "#{dest}#{serial}" )
		end
	end
db.close

