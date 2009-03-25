#
# RuBBS
#
# Copyright (C) 2001, All right reserved by TADA Tadashi <sho@spc.gr.jp>
# You can redistribute it and/or modify it under GPL2.
# $Revision: 1.22 $
#
RUBBS_VERSION = '1.0.7'

begin
	require 'gdbm'
	DBClass = GDBM
	DB_SUFFIX = '.gdb'
rescue LoadError
	begin
		require 'dbm'
		DBClass = DBM
		DB_SUFFIX = ''
	rescue LoadError
		require 'sdbm'
		DBClass = SDBM
		DB_SUFFIX = '.sdb'
	end
end
require 'cgi'
require 'nkf'
require 'erb/erbl'
require 'lock'

#
# enhanced String class
#
class String
	SALT_CHARSET = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
	def String::salt
		result = '$1$'
		10.times do
			result << SALT_CHARSET[rand( 64 )]
		end
		result
	end

	def make_link
		return self.gsub( / /, "\001" ).
			gsub( /</, "\002" ).
			gsub( />/, "\003" ).
			gsub( %r|http[s]{0,1}://[\(\)%#!/0-9a-zA-Z_$@.&+-,'"*=;?:~-]+|, '<a href="\&">\&</a>' ).
			gsub( %r|ftp://[\(\)%#!/0-9a-zA-Z$-_@.&+-,'"*=;?:~]+|, '<a href="\&">\&</a>' ).
			gsub( %r|[0-9a-zA-Z_.-]+@[\(\)%!0-9a-zA-Z_$@.&+-,'"*-]+|, '<a href="mailto:\&">\&</a>' ).
			gsub( /&/, '&amp;' ).
			gsub( /\003/, '&gt;' ).
			gsub( /\002/, '&lt;' ).
			gsub( /\001/, '&nbsp;' ).
			gsub( /\t/, '&nbsp;' * 8 )
	end

	def quote
		quoted = ''
		self.each_line do |line|
			quoted += line.sub( /^\s*(>|&gt;).*\n*/, %|<span class="quote">#{line.chomp}</span>\n| )
		end
		return quoted
	end

	def nkf( charset )
		case charset
		when /iso-2022-jp/i
			self.to_jis
		when /euc-jp/i
			self.to_euc
		when /sjis/i, /shift_jis/i
			self.to_sjis
		else
			self.clone
		end
	end

	def native
		case $KCODE[0]
		when ?E, ?e
			self.to_euc
		when ?S, ?s
			self.to_sjis
		else
			self.clone
		end
	end
	def to_jis; NKF::nkf( '-m0 -jXd', self ); end
	def to_euc; NKF::nkf( '-m0 -eXd', self ); end
	def to_sjis; NKF::nkf( '-m0 -sXd', self ); end
end

#
# enhanced CGI class
#
class CGI
	def valid?( param, idx = 0 )
		self.params[param] and self.params[param][idx] and self.params[param][idx].length > 0
	end
end

#
# enhanced Time class
#
class Time
	def rfc1123_date
		self.clone.gmtime.strftime( '%a, %d %b %Y %X GMT' )
	end
end

#
# an Article
#
class Article
	attr_reader :name, :mail, :subject, :date, :remote, :contents, :reply_to

	def Article::decode( str )
		article = Article::new
		article.decode( str )
	end

	def initialize( name='', mail='', subject='(No Subject)', contents = '', nowrap = false, reply_to = '' )
		@name, @mail, @subject, @contents, @nowrap, @reply_to = name, mail, subject, contents, nowrap, reply_to
		@contents.sub!( /\n+\z/, '' )
		@date = Time.now.strftime( '%Y/%m/%d %H:%M:%S %Z' ).native
		@remote = ENV['REMOTE_ADDR']
		@status = "alive"
	end
	
	def equals?( article )
		if @name == article.name and
				@subject == article.subject and
				@contents.strip == article.contents.strip then
			true
		else
			false
		end
	end

	def decode( str )
		header = true
		str.each_line do |line|
			if header then
				case line
				when /^name: (.*)$/
					@name = $1
				when /^mail: (.*)$/
					@mail = $1
				when /^subject: (.*)$/
					@subject = $1
				when /^date: (.*)$/
					@date = $1
				when /^nowrap: true$/
					@nowrap = true
				when /^status: (.*)$/
					@status = $1
				when /^remote: (.*)$/
					@remote = $1
				when /^reply_to: (.*)$/
					@reply_to = $1
				else
					header = false if /^$/ =~ line
				end
			else
				@contents += line
			end
		end
		@contents.sub!( /\n+\z/, '' )
		self
	end

	def alive
		@status = 'alive'
	end

	def remove
		@status = 'remove'
	end

	def alive?
		@status == 'alive'
	end

	def encode
		return	"name: #{@name}\n" +
					"mail: #{@mail}\n" +
					"subject: #{@subject}\n" +
					"remote: #{@remote}\n" +
					"date: #{@date}\n" +
					"reply_to: #{@reply_to}\n" +
					"nowrap: #{@nowrap}\n" +
					"status: #{@status}\n" +
					"\n#{@contents}\n"
	end

	def html_contents
		c = @contents.make_link.quote
		if @nowrap then
			'<pre>' + c + '</pre>'
		else
			c.gsub( /\n/, "<br />\n" )
		end
	end
end

#
# a Board
#
class Board
	class BoardError < StandardError; end
	class BoardConfigError < BoardError; end
	class BoardBadOperation < BoardError; end

	attr_reader :name, :action, :encoding, :latest
	VIEW = 0
	MAINTENANCE = 1
	CONFIGURE = 2
	REMOVE = 3
	RESTORE = 4
	APPEND = 5
	REPLY = 6

	def initialize( cgi )
		begin
			@cgi = cgi
			@cgi_url = @cgi.script_name
			@name = File::basename( @cgi_url ).sub( /\..*$/, '' )
			
			# loading configuration
			load_conf

			# set action
			begin
				eval( "@action = #{@cgi.params['action'][0].upcase}" )
			rescue NameError
				@action = VIEW
			end
		rescue
			raise BoardConfigError::new( $!.to_s )
		end

		# other variables
		@top = 0
		@cookie = nil
		@m_msg = nil
		@m_serial = nil
	end

	def transaction
		raise BoardError::new( 'call with block' ) if not iterator?
		begin
			@db = DBClass::open( "#{@name}#{DB_SUFFIX}" )
			@latest = (@db['latest'] or '1').to_i
			@last_modified = @db['last_modified'] or Time::now.rfc1123_date
			yield
		ensure
			@db.close if @db
		end
	end

	def header( opt = nil )
		hash = {
			'type' => 'text/html',
			'charset' => @encoding,
		}
		opt.each do |k,v| hash[k] = v end if opt
		hash['Cache-Control'] = 'no-cache' if @action != VIEW
		hash['cookie'] = @cookie if @cookie
		@cgi.header( hash )
	end

	def maintenance
		if not @password or
				(@cgi.valid?( 'password' ) and @cgi.params['password'][0].crypt( @password ) == @password) then
			ERbLight::new( open_rhtml( '.conf.rhtml' ) ).result( binding ).nkf( @encoding )
		else
			raise BoardBadOperation::new( 'password unmatched' )
		end
	end

	def configure
		check_password do
			if @cgi.valid?( 'password' ) then
				if @cgi.params['password'][0] != @cgi.params['password2'][0] then
					@m_msg = @password_diff
					return maintenance
				else
					@new_password = @cgi.params['password'][0].crypt( String::salt )
				end
			else
				@new_password = @password
			end
			conf = ERbLight::new( open_rhtml( '.conf.rtxt' ) ).result( binding )
			File::open( "#{@name}.conf.new", 'w' ) do |f|
				f.write( conf )
			end
			File::delete( "#{@name}.conf~" ) if File::exist?( "#{@name}.conf~" )
			File::rename( "#{@name}.conf", "#{@name}.conf~" );
			File::rename( "#{@name}.conf.new", "#{@name}.conf" );
			load_conf
		end
		view
	end

	def remove
		check_password do
			if @cgi.valid?( 'serial' ) then
				serial = @cgi.params['serial'][0].sub( /^0+/, '' )
				if @db[serial] then
					article = Article::decode( @db[serial].native )
					if article.alive? then
						article.remove
						@db[serial] = article.encode.native
						@m_msg = @remove_success
					else
						@m_msg = @remove_fail
					end
				else
					@m_msg = @remove_fail
				end
				@m_serial = serial
			end
			return ERbLight::new( open_rhtml( '.conf.rhtml' ) ).result( binding ).nkf( @encoding )
		end
		raise BoardBadOperation::new( 'password unmatched' )
	end

	def restore
		check_password do
			if @cgi.valid?( 'serial' ) then
				serial = @cgi.params['serial'][0].sub( /^0+/, '' )
				if @db[serial] then
					article = Article::decode( @db[serial].native )
					if not article.alive? then
						article.alive
						@db[serial] = article.encode.native
						@m_msg = @restore_success
					else
						@m_msg = @restore_fail
					end
				else
					@m_msg = @restore_fail
				end
				@m_serial = serial
			end
			return ERbLight::new( open_rhtml( '.conf.rhtml' ) ).result( binding ).nkf( @encoding )
		end
		raise BoardBadOperation::new( 'password unmatched' )
	end

	def view
#		if @cgi.valid?( 'serial' ) then
#			serial = @cgi.params['serial'][0].to_i
#			ERbLight::new( open_rhtml( '.one.rhtml' ) ).result( binding ).nkf( @encoding )
#		else
			ERbLight::new( open_rhtml( '.view.rhtml' ) ).result( binding ).nkf( @encoding )
#		end
	end

	def form
		subject, content = '', ''
		serial, = @cgi.params['serial']
		if @cgi.valid?( 'serial' ) and (str = @db[serial] ) then
			a = Article::decode( str.native )
			subject = 'Re: ' + a.subject.sub( /^(re:\s*)+/i, '' )
			content = CGI::escapeHTML( a.contents.to_a.collect{|s|'>'+s}.join + "\n" )
		end
		name = @cgi.cookies['rubbs'][0] or ''
		mail = @cgi.cookies['rubbs'][1] or ''
		ERbLight::new( open_rhtml( '.form.rhtml' ) ).result( binding ).nkf( @encoding )
	end

	def post
		return if not @cgi.valid?( 'name' )
		name = @cgi.params['name'][0].native
		mail = @cgi.params['mail'][0].native
		subject = @cgi.valid?( 'subject' ) ? @cgi.params['subject'][0] : '(No Subject)'
		@reply_to = @cgi.valid?( 'reply_to' ) ? @cgi.params['reply_to'][0] : ''
		contents = @cgi.params['contents'][0].native
		nowrap = @cgi.valid?( 'nowrap' ) ? true : false
		article = Article::new( name, mail, subject.native, contents, nowrap, @reply_to )
		if @latest > 1 then # duplication check
			prev = Article::decode( @db[(@latest-1).to_s].native )
			return if prev and article.equals?( prev )
		end
		@db[@latest.to_s] = article.encode.native
		sendmail( @latest, article ) if not @mail_to.empty?
		@db['latest'] = (@latest += 1).to_s
		@db['last_modified'] = @last_modified = Time::now.rfc1123_date

		@cookie = CGI::Cookie::new( {
				'name' => 'rubbs',
				'value' => [name,mail],
				'path' => @cgi_url,
				'expires' => Time::now.gmtime + 24*60*60*30
		} )
	end

private

	def each_article
		raise BoardError::new( 'call with block' ) if not iterator?

		if @cgi.valid?( 'top' ) and not @cgi.valid?( 'ignore_top' ) then
			@top = @cgi.params['top'][0].to_i
			@top = @latest - 1 if @top >= @latest
		else
			@top = @latest - 1
		end

		@bottom = @top - @limit_per_page.to_i + 1
		@bottom = 1 if @bottom < 1

		@top.downto( @bottom ) do |serial|
			str = @db[serial.to_s]
			yield( serial, Article::decode( str.native ) ) if str
		end
	end

	def load_conf
		[	"conf/default.conf", "#{@name}.conf" ].each do |file|
			eval( File::readlines( file ).join )
		end
		[@keywords, @title, @header1, @header, @footer].each do |s|
			s.chomp! if s
		end
		lang = @encoding=='ISO-8859-1' ? 'en' : 'ja'
		eval( File::readlines( "conf/default.#{lang}.conf" ).join )
	end

	def open_rhtml( suffix )
		begin
			File::readlines( "#{@name}#{suffix}" ).join
		rescue Errno::ENOENT
			File::readlines( "conf/default#{suffix}" ).join
		end
	end

	def check_password
		if not @password or
				(@cgi.valid?( 'crypt' ) and @cgi.params['crypt'][0] == @password) then
			yield
		end
	end

	def sendmail( serial, article )
		return if not ($rubbs_smtp_host and $rubbs_smtp_from)

		case @lang
		when /^ja/
			name = to_mime( article.name )
			subject = to_mime( article.subject )
		else
			name = article.name
			subject = article.subject
		end
		mail = article.mail.length == 0 ? 'anonymous@unknown' : article.mail
		reply = @mail_reply
		if /^ja/ =~ @lang then
			encoding = 'ISO-2022-JP'
		else
			encoding = @encoding
		end
		contents = article.contents

		now = Time::now
		g = now.dup.gmtime
		l = Time::local( g.year, g.month, g.day, g.hour, g.min, g.sec )
		tz = (g.to_i - l.to_i) / 36
		date = now.strftime( "%a, %d %b %Y %X " ) + sprintf( "%+05d", tz )


		begin
			require 'net/smtp'
			message_id = "<#{@name}.#{serial}@#{Socket::gethostname.sub(/^.+?\./,'')}>"
			if not @reply_to.empty?
				@in_reply_to = "<#{@name}.#{@reply_to}@#{Socket::gethostname.sub(/^.+?\./,'')}>"
			end
			text = ERbLight::new( File::readlines( 'conf/mail.rtxt' ).join ).result( binding )
			text = text.to_jis if /^ja/ =~ @lang
			ENV['HOSTNAME'] = Socket::gethostname if not ENV['HOSTNAME'] # for Ruby 1.4's net/smtp
			Net::SMTP.start( $rubbs_smtp_host, 25 ) do |smtp|
				smtp.ready( $rubbs_smtp_from, @mail_to ) do |adapter| adapter.write( text ) end
			end
			File::open( 'mail.log', 'a' ) do |f|
				f.puts Time::now
				f.puts "succeed."
			end if $DEBUG
		rescue
			File::open( 'mail.log', 'a' ) do |f|
				f.puts Time::now
				f.puts $!
				f.puts $@.join( "\n" )
			end if $DEBUG
		end
	end

	def to_mime( str )
		"=?ISO-2022-JP?B?" + [str.to_jis].pack( 'm' ).gsub( /\n/, '' ) + "?="
	end
end

#
# RuBBS main class
#
class RuBBS
	def initialize
		begin
			eval( File::readlines( "rubbs.conf" ).join )
			$rubbs_smtp_host = @smtp_host if @smtp_host
			$rubbs_smtp_from = @smtp_from if @smtp_from
			
			cgi = CGI::new
			@bbs = Board::new( cgi )
			Lock::lock( "lock/#{@bbs.name}" ) do
				head = @bbs.header
				body = nil
				@bbs.transaction do
					case @bbs.action
					when Board::MAINTENANCE
						body = @bbs.maintenance
					when Board::CONFIGURE
						@bbs.configure
						update_html( @bbs )
						jump_html( @bbs )
					when Board::REMOVE
						body = @bbs.remove
						update_html( @bbs )
					when Board::RESTORE
						body = @bbs.restore
						update_html( @bbs )
					when Board::REPLY
						body = @bbs.form
					when Board::APPEND
						@bbs.post
						update_html( @bbs )
						jump_html( @bbs )
					else
						if cgi.valid?( 'serial' )
							body = @bbs.view
						elsif cgi.valid?( 'top' ) and not cgi.valid?( 'ignore_top' ) then
							body = @bbs.view
						elsif cgi.valid?( 'effect' ) and cgi.params['effect'][0] == 'yes' # making static HTML
							update_html( @bbs )
							jump_html( @bbs )
						else
							jump_html( @bbs )
						end
					end # case
				end # transaction
				if body then
					print head
					print body
				end
			end # lock
		rescue Lock::LockError 
			throw_html( cgi, 'conf/rubbs.lock.rhtml' )
		rescue Board::BoardBadOperation
			jump_html( @bbs )
		rescue # other errors
			throw_html( cgi, 'conf/rubbs.unknown.rhtml' )
		end
	end

	def update_html( bbs )
		File::open( "#{@path}#{bbs.name}.html", 'w' ) do |f|
			f.write( bbs.view )
		end
	end

	def jump_html( bbs )
		url = "#{@url}#{bbs.name}.html"
		url += "?post=#{bbs.latest-1}" if bbs.action == Board::APPEND
		print @bbs.header( { 'Location' => url} )
	end

	def throw_html( cgi, file )
		encoding = 'ISO-8859-1'
		lang = 'en_JS'
		if ENV['HTTP_ACCEPT_LANGUAGE'] then
			case ENV['HTTP_ACCEPT_LANGUAGE'].gsub( /\s+/, '' )
			when /^ja/
				encoding = 'ISO-2022-JP'
				lang = 'ja-JP'
			end
		end
		print cgi.header( { 'type' => 'text/html', 'charset' => encoding } )
		rhtml = File::readlines( file ).join
		print ERbLight::new( rhtml ).result( binding ).nkf( encoding )
	end
end

