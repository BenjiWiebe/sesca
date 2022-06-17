#!/usr/bin/ruby
require 'pry'
require 'selenium-webdriver'
require 'nokogiri'
require 'json'
require 'yaml'

DEBUG=false
DRYRUN=false

cfgfile = 'sesca.config'
cfg = YAML.load(File.open(cfgfile).read)
username = cfg["username"]
password = cfg["password"]
selenium_remote_ip = cfg["selenium_remote_ip"]

if [selenium_remote_ip,password,username].include?(nil)
    raise "Make sure all configuration fields are populated!"
end

print "Initializing driver... "

if DEBUG
	# If I am using the remote version, I need to accept insecure certs because of the SSL-intercepting Internet filter.
	caps = Selenium::WebDriver::Remote::Capabilities.firefox(accept_insecure_certs: true)
	driver = Selenium::WebDriver.for :remote, url: "http://#{selenium_remote_ip}:4444/", desired_capabilities: caps
else
	opts = Selenium::WebDriver::Options.firefox
	opts.headless!
	driver = Selenium::WebDriver.for :firefox, capabilities: opts
end

if DRYRUN
	driver.quit
	puts "Dry run ended."
	exit
end

wait = Selenium::WebDriver::Wait.new(:timeout => 35)

print "done\nLoading login page... "
driver.get('https://sca.cdcstihl.biz/sca-dev-kilimanjaro/checkout.ssp?is=login&login=T#login-register')
loginemail = nil
loginemail = wait.until { driver.find_element(:id, "login-email") }
puts "done"
loginpassword = driver.find_element(:id, "login-password")
loginemail.send_keys(username)
loginpassword.send_keys(password)
loginbutton = driver.find_element(:class, "login-register-login-submit")
print "Logging in... "
loginbutton.click

signout = wait.until { driver.find_element(:class, "header-menu-myaccount-signout-link") }

# We are directly navigating here instead of clicking the button because the button changes depending on 
# the size of the browser window.
print "done\nLoading account... "
driver.get('https://sca.cdcstihl.biz/sca-dev-kilimanjaro/my_account.ssp?fragment=overview')

purchasehistory = wait.until { driver.find_element(:class, "overview-home-orders-title-link") }
print "done\nLoading purchase history... "
purchasehistory.click

# Now we are on the recent orders page, let's go to the open orders page
openorders = wait.until { driver.find_element(:class, "order-history-list-header-button-open") }
print "done\nLoading open orders... "
openorders.click

# On the open orders list, let's click the first order in the list for an example.
#firstitem = wait.until { driver.find_element(:class, "recordviews-actionable-title") }
#firstitem.click
#driver.navigate.back

# Wait until purchase history loads
wait.until { driver.find_element(:class, "recordviews-actionable-title") }
puts "done"


r=driver.find_elements(:class, "recordviews-actionable-title")
ponumbers = r.map {|x| x.attribute("innerText") }
podata = []

ponumbers_count = ponumbers.length
ponumbers.each_with_index do |ordernumber, onindex|
	print "Loading order number #{ordernumber}: #{onindex+1}/#{ponumbers_count}... "
	orderelem = driver.find_element(xpath: "//span[@class='tranid' and text()='#{ordernumber}']")
	orderelem.click
	wait.until { driver.find_element(:class, "order-history-details-header-date-info-date-label") }
	# do stuff with order page here
	dateelem = driver.find_element(:class, "order-history-details-header-date")
	date = dateelem.attribute("innerText")
	sections = driver.find_elements(:class, "order-history-packages-acordion-divider")
	
	section_data = []
	sections.each do |section|
		nsec = Nokogiri::HTML(section.attribute("innerHTML"))
		shipped_date = nsec.css(".order-history-packages-shipped-date-value").text
		tracking_details_elems = nsec.css('.order-history-list-tracking-number-control-numbers-link')
		tracking_details = {}
		tracking_details_elems.each do |tr|
			tr_link = tr['href']
			tr_number = tr.text
			tracking_details[tr_number] = tr_link
		end
		is_shipped = !shipped_date.empty?
		item_entries = nsec.css(".transaction-line-views-cell-actionable-table-middle")
		items = []
		item_entries.each do |it|
			partno = it.css('.transaction-line-views-cell-actionable-name-link').text.lstrip.rstrip
			qty = it.css('.transaction-line-views-quantity-amount-value').text.to_i
			cost = it.css('.transaction-line-views-price-lead').text.rstrip.lstrip
			srp = it.css('.transaction-line-views-price-old').text.gsub(/^ - SRP: /, '')
			itemdata = {partno: partno, qty: qty, cost: cost, srp: srp}
			items << itemdata
		end
		section_data << {shipped: is_shipped, shipdate: shipped_date, tracking: tracking_details, items: items}
	end

	podata << {order: ordernumber, date: date, sections: section_data}
	puts "done"

	driver.navigate.back
end
print "Saving data... "
File.write("sesca_out.json", podata.to_json)
puts "done"
driver.quit
