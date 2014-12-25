require 'net/http'
require 'json'
require 'time'
 
############################################################ 
#widget constants
############################################################
#Jenkins server base URL
JENKINS_URI = URI.parse("http://127.0.0.1:8080/jenkins")
 
#change to true if Jenkins is using SSL
JENKINS_USING_SSL = false
 
#credentials of Jenkins user (give these values if the above flag is true)
JENKINS_AUTH = {
  'name' => nil,
  'password' => nil
}
 
#Hash of all Jenkins jobs to be monitored for SCM changes, mapped to their event IDs
#Add your Jenkins jobs & their associated unique event IDs here
$jenkins_jobs_to_be_monitored = {
  'build_web_app' => 'build_web_app'
}
 
#Trim thresholds (widget display)
COMMIT_MESSAGE_TRIM_LENGTH = 120
FILE_LIST_TRIM_LENGTH = 4
MAX_FILENAME_LENGTH = 100
FILENAME_TAIL_LENGTH = 30
 
#helper function that trims file names
#for long filenames, this function keeps all chars up to the 
#trim length, inserts an elipsis and then keeps the "tail" of the file name
# My_extra_long_file_name.cpp => My_extra...file_name.cpp
def trim_filename(filename)
  filename_length = filename.length
  
  #trim 'n' splice if necessary
  if filename_length > MAX_FILENAME_LENGTH
    filename = filename.to_s[0..MAX_FILENAME_LENGTH] + '...' + filename.to_s[(filename_length - FILENAME_TAIL_LENGTH)..filename_length]
  end
  
  return filename
end
 
#helper function which fetches JSON for job changeset
def get_json_for_job_changeset(job_name, build = 'lastBuild')
  begin
    job_name = URI.encode(job_name)
    #http = Net::HTTP.new(JENKINS_URI.host, JENKINS_URI.port)
    
    #url = "/job/#{job_name}/#{build}/api/json?tree=changeSet[*[*[*]]]"
    #request = Net::HTTP::Get.new(url)
    

    uri = URI.parse("http://127.0.0.1:8080/jenkins/job/#{job_name}/#{build}/api/json?tree=changeSet[*[*[*]]]")
    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Get.new(uri.request_uri)

    #check if Jenkins is implementing SSL
    #if JENKINS_USING_SSL == false
    #  http.use_ssl = true
    #  http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    #end
    
    
    response = http.request(request)
    puts "Agora vai"
    puts response.body
    JSON.parse(response.body)
  rescue Exception => e
    raise e
  end
end
 
 
#scheduled job
SCHEDULER.every '5s' do
  begin
    #iterate over all Jenkins jobs in the hash
    $jenkins_jobs_to_be_monitored.each do |jenkins_job_name, widget_event_id|
    
      #fetch changeset information for selected job
      commit_info = get_json_for_job_changeset(jenkins_job_name)
      commit_items = commit_info["items"]
    
      # check if the "items" array item contains elements
      # Note: "items" may be empty, for example when Jenkins is in the process of building the 
      # job which is being monitored for changes
      if !commit_info["changeSet"]["items"].empty?
       
        #check if we're dealing with git
        if commit_info["changeSet"]["kind"] == 'git'
          commit_id = commit_info["changeSet"]["items"][0]["commitId"]
          commit_date = commit_info["changeSet"]["items"][0]["date"]
        else
          #not using git - fall back to Perforce JSON structure
          commit_id = commit_info["changeSet"]["items"][0]["author"]["id"]
          commit_date = commit_info["changeSet"]["items"][0]["date"]
          puts commit_id
          puts commit_date

        end
        
        #extract commit information fields from Jenkins JSON response
        author_name = commit_info["changeSet"]["items"][0]["author"]["fullName"]
        puts author_name
        
        #process commit message
        commit_message = commit_info["changeSet"]["items"][0]["msg"]
        puts commit_message
 
        #trim message length if necessary
        if commit_message.length > COMMIT_MESSAGE_TRIM_LENGTH
          commit_message = commit_message.to_s[0..COMMIT_MESSAGE_TRIM_LENGTH].gsub(/[^\w]\w+\s*$/, ' ...')
        end
        
        #build up list of affected files
        file_items = commit_info["changeSet"]["items"][0]["affectedPaths"]
        affected_items = Array.new
        
        #add key-value pair for each file found
        file_items.sort.each { |x| affected_items.push( {:file_name => trim_filename(x)} ) }
        
        #trim file list length if necessary
        if affected_items.length > FILE_LIST_TRIM_LENGTH
          length = affected_items.length
          affected_items = affected_items.slice(0, FILE_LIST_TRIM_LENGTH)
          
          #add indication of total number of affected files
          affected_items[FILE_LIST_TRIM_LENGTH] = {:file_name => '  ...  (' + length.to_s + ' files in total)'}
        end
        
        puts "chegou!!"
        json_formatted_data = Hash.new
        json_formatted_data[0] = { id: commit_id, timestamp: commit_date, message: commit_message, author: author_name }
        puts json_formatted_data[0]

        #send event to dashboard
        send_event(widget_event_id, commit_entries: json_formatted_data.values, commit_files: affected_items)
     
      else
        #Jenkins is busy
        print "[Fetching changeSet from Jenkins] JSON object doesn't contain data ... \n"
      end    
    end
    
  rescue Exception => e
    #exception encountered 
    print "Oops! exception encountered!\n"
    print e.message
    print "\n"
  end
end