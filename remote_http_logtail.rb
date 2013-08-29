require 'uri'
require 'net/http'
require 'net/https'

#This code snippet acts like 'tail' for hosted (log) files, it reads up the last updated bytes instead of the whole file,
#allowing the lazy administrator to not download the entire log.
#
#The script depends on the fact that the server supports range byte requests, and wont block them,
#using some WAF if there are too many requests
#
#If you have ssh access to the log files, use ssh!
#
##{url} is a log file only accessible over http and is being updated/appended to.
#
#Todo
#- Allow reading the reading upto x bytes from the end (fetchsize to be passed as an arg)
#- Dump lines for the last hour or other variables.
#- grep --color functionality
#- https

url = ''

fetchsize = 1000 #in bytes
poll_interval = 1

def http_request(url, request_type, size=nil)
	
	headers = { 'Range' => "bytes=#{size}"}
	params = url.split('?',2)[1]
	
	uri = URI(url)
	http = Net::HTTP.new(uri.host, uri.port)
	
	if uri.path.empty?
		path = '/'
	else
		path = uri.path
	end	
	
	if request_type == 'head'
		content = http.head(path, headers)
		return [ content.code, content.header ]
	else
		content = http.get(path, headers)
		return [ content.code, content.header, content.body ]
	end

end

def check_statuscode(statuscode)
	if ! (statuscode >= 200 && statuscode < 300 )
		puts statuscode
		puts 'eh, something went wrong there - non 200 response'
		exit(1)
	else
		return 0
	end	
end

def split_filesize(header)
	
	if header.nil?
		puts 'empty header recieved'
		exit(1)
	else
		#bytes 100076458-100077457/100077458
#		puts header.get_fields('Content-Range').inspect
		range_start, range_end = header.get_fields('Content-Range')[0].split()[1].split('/')[0].split('-')
		filesize = header.get_fields('Content-Range')[0].split('/')[1].to_i
 
#		puts range_start + ' ' +  range_end + ' ' +  filesize.to_s
#		str = header.get_fields('Content-Range')[0].split('/')[1].to_i
		return [range_start, range_end, filesize]
	end	

end


#first check the length of the remote file, and if range requests are supported.
minsize="-1" #use a small range for the test
statuscode, header = http_request(url, 'get', minsize)
if  check_statuscode(statuscode.to_i)
			range_start, range_end, curr_filesize = split_filesize(header)
			#puts range_start + ' ' +  range_end + ' ' +  curr_filesize.to_s
			if curr_filesize == 0
				puts 'remote file is zero length... retrying utill we have something to show'
				exit(1)
			else
				prev_filesize=0 #set to default since its the first run
			end	
end

action='reverse_tail'
#handle filesize smaller than fetchsize
if action == 'tail'
	if curr_filesize >=	fetchsize 
		range='-' + fetchsize.to_s
	else
		range='-' + curr_filesize.to_s
	end	
end

#byte_mark_a  points to the bottom of the chunk
#byte_mark_b pointes to the top of the chunk
#e.g if content header == ["bytes", "21347742-21347942/21347943"]
#byte_mark_a=21347943
#byte_mark_b=byte_mark_a-fetchsize 
#range request is done with headers = { 'Range' => "bytes=byte_mark_b-byte_mark_a"}

if action == 'reverse_tail'
	byte_mark_a = curr_filesize
	if curr_filesize > fetchsize
		byte_mark_b = curr_filesize-fetchsize 
	else
		byte_mark_b = 0
	end
	range = byte_mark_b.to_s + '-' + byte_mark_a.to_s
end	



def split_chunk(chunk, delimiter, is_last_chunk, str_half)
  
  str_buf = chunk.split(delimiter).reverse #reverse our array, since we reading upwards
  
  if str_half # if a previous half is present, add it to the first string in the array
	str_buf[0].concat(str_half)
  end
 
 	if is_last_chunk != 1    # remove the last string from the array, since its possibly  half,
	  str_half = str_buf.pop # if its the last chunk, leave str_buf as is.    
	end

  [str_buf, str_half]
end


str_half=nil
is_last_chunk=-1
loop {
	#puts 'R -> ' + range.to_s	
	statuscode, header, body = http_request(url, 'get', range)
	
	if check_statuscode(statuscode.to_i)
		prev_filesize=curr_filesize
		range_start, range_end, curr_filesize = split_filesize(header) #get details from the Content-Range header
		
		if action == 'reverse_tail'
		
			if byte_mark_b > fetchsize
				byte_mark_a=byte_mark_b-1 # read one less character from where b pointed to earlier, hence the -1
				byte_mark_b=byte_mark_b-fetchsize
			else
				puts 'Its the last chunk, we wait for another iteration'
				is_last_chunk+=1
				byte_mark_a=byte_mark_b-1
				byte_mark_b=0 #else we just read everthing till the top end of the file
			end
			range = byte_mark_b.to_s + '-' + byte_mark_a.to_s
		end
		
		if action == 'tail'
			if curr_filesize > prev_filesize
				range = ( curr_filesize - prev_filesize ) + 1 #range requests seems to return requested bytes -1 
				range= '-' + range.to_s
			else 
				range=0		
			end
		end	

	end

	str, str_half = split_chunk(body, "\n", is_last_chunk, str_half)
	puts str
	exit if is_last_chunk == 1

#	puts str
	#str.each{|line| puts line }	
#	puts str

	sleep poll_interval 
}
