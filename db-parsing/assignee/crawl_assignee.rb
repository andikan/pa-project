#!/usr/bin/env ruby
# encoding: UTF-8

require 'nokogiri'
require 'open-uri'
require 'watir-webdriver'
require 'lib/connect_mysql'

start_time = Time.now   #process time count

mysql = Connect_mysql.new('chuya', '0514')
mypaper = mysql.db('mypaper') #input db
patentproject = mysql.db('patentproject2012') #output db

#prompt year and limit
print "Input year:"
query_year = gets.chomp.strip
print "Input LIMIT:"
query_limit = gets.chomp.strip

logfile_assignee = File.open('db-parsing/assignee/log/crawl_assignee_#{query_year}_#{query_limit}.log','w+') #output file
logfile_assignee.write("Crawling Assignee from USPTO -- #{query_year}\n")

logfile_without = File.open('db-parsing/assignee/log/crawl_without_assignee_#{query_year}_#{query_limit}.log','w+') #output file
logfile_without.write("Without Assignee or Error from USPTO -- #{query_year}\n")

patent_2009 = mypaper.query("SELECT Patent_id FROM content_#{query_year} ORDER BY Patent_id ASC #{query_limit}") #fetch patent id
browser = Watir::Browser.new :ff #open firefox
browser.goto 'http://patft.uspto.gov/netahtml/PTO/srchnum.htm'

with_assignee, without_assignee, page_error = [], [], []
  
auto_index = query_limit[5..-1].split(',')[0].to_i + 1
patent_2009.each do |p|
  browser.text_field(:name => 'TERM1').set p['Patent_id']
  browser.button(:value => 'Search').click
  
  begin
    Watir::Wait.until { browser.title.include? 'United States Patent:' }
  rescue Watir::Wait::TimeoutError => e
    puts e.to_s
    sleep(1)   
    retry
  end

  page_title = browser.title
  #check patent id and web page title
  if !page_title.match(/#{p['Patent_id']}/).nil?  #title == patent id
    if browser.html.match(/Assignee:/).nil? #without assignee
      without_assignee.push(p['Patent_id'])
      s = "Index:#{auto_index}  =>  Patent_id:#{p['Patent_id']}  =>  without assignee\n"
      puts s
      logfile_without.write(s)
    else #have assignee
      with_assignee.push(p['Patent_id'])
      assignee = []
      location = []
      assignee_with_location = browser.table(:index => 3).tbody.tr(:index => 1).td(:index => 1).text.split("\n")
      assignee_td = Nokogiri::HTML(browser.table(:index => 3).tbody.tr(:index => 1).html).css('td')[1]
      assignee_array = assignee_td.to_s.split("<br>")
      (0..assignee_array.count-2).each do |i|
        assignee.push(Nokogiri::HTML(assignee_array[i]).css('b')[0].text)
      end
      
      if assignee.count == assignee_with_location.count  #double check   
        assignee_with_location.each do |al|  #location = assignee_with_location - assignee
          index = assignee_with_location.index(al)
          location.push(al[assignee[index].length..-1].strip)
        end
        
        (0..assignee.count-1).each do |i|
          s = "Index:#{auto_index}  =>  Patent_id:#{p['Patent_id']}  =>  Assignee:#{assignee[i]}  =>  Location:#{location[i]}\n"
          puts s
          logfile_assignee.write(s)
          pid = p['Patent_id']
          modify_assignee = assignee[i].gsub(/'/, "''")
          modify_location = location[i].gsub(/'/, "''")
          patentproject.query("INSERT INTO assignee (Patent_id, Assignee, Location)
                               VALUES ('#{pid}', '#{modify_assignee}', '#{modify_location}') ")
        end                
        
      else  #error occur
        s = "Index:#{auto_index}  =>  Patent_id:#{p['Patent_id']}  =>  a_l.count = #{assignee_with_location.count} != assignee.count = #{assignee.count}\n"
        puts s
        logfile_without.write(s)
      end
    end
    
  else  #when title != patent id
    page_error.push(p['Patent_id'])
    s = "Index:#{auto_index}  =>  Patent_id:#{p['Patent_id']}  =>  page title [ #{page_title} ] does not equal to patent id\n"
    puts s
    logfile_without.write(s)
  end

  browser.goto 'http://patft.uspto.gov/netahtml/PTO/srchnum.htm'
  auto_index += 1
end

s = "with_assignee = #{with_assignee.count}\n"+
"without_assignee = #{without_assignee.count}\n"+
"page_error = #{page_error.count}\n"+
"total = #{with_assignee.count+without_assignee.count+page_error.count}\n\n"+
"Page Error Patent_id = #{page_error}\n\n"+
"Process Duration: #{Time.now - start_time} seconds"
puts s
logfile_assignee.write(s)

browser.close
logfile_assignee.close
logfile_without.close

