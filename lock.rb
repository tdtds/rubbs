#
# Lock module
#
# Copyright (C) 2001, All right reserved by TADA Tadashi <sho@spc.gr.jp>
# You can redistribute it and/or modify it under GPL2.
#
module Lock
	class LockError < StandardError; end

	def Lock::lock( basefile = 'lock/lock', try = 10, timeout = 600 )
		locking = false
		lockfile = "#{basefile}.#$$.#{Time.now.to_i}"
		try.times do
			begin
				File.rename( basefile, lockfile )
				locking = true
				break
			rescue #rename failed
				begin
					Dir.glob( "#{basefile}.*" ).each do |oldlock|
						if /^#{basefile}\.\d+\.(\d+)/ =~ oldlock and
								Time.now.to_i - $1.to_i > timeout then
							File.rename( oldlock, lockfile )
							locking = true
							break
						end
					end
				rescue
				end
			end
			sleep( 1 )
		end
		raise Lock::LockError, "LockError: #{lockfile} #{$!}" unless locking
		if iterator? then
			begin
				yield
			ensure
				Lock::unlock( lockfile, basefile ) if locking
			end
		else
			return lockfile
		end
	end

	def Lock::unlock( lockfile, basefile = 'lock/lock' )
		File.rename( lockfile, basefile )
	end
end
