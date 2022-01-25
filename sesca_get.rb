#!/usr/bin/ruby
require 'pry'
require 'selenium-webdriver'
require 'nokogiri'
require 'json'
require 'yaml'

cfgfile = 'sesca.config'
cfg = YAML.load(File.open(cfgfile).read)
username = cfg["username"]
password = cfg["psssword"]
selenium_remote_ip = cfg["selenium_remote_ip"]

if [selenium_remote_ip,password,username].include?(nil)
    raise "Make sure all configuration fields are populated!"
end

caps = Selenium::WebDriver::Remote::Capabilities.firefox(accept_insecure_certs: true)
driver = Selenium::WebDriver.for :remote, url: "http://#{selenium_remote_ip}:4444/", desired_capabilities: caps
wait = Selenium::WebDriver::Wait.new(:timeout => 35)

driver.get('https://sca.cdcstihl.biz/sca-dev-kilimanjaro/checkout.ssp?is=login&login=T#login-register')
puts driver.title
loginemail = nil
loginemail = wait.until { driver.find_element(:id, "login-email") }
loginpassword = driver.find_element(:id, "login-password")
loginemail.send_keys(username)
loginpassword.send_keys(password)
loginbutton = driver.find_element(:class, "login-register-login-submit")
loginbutton.click

signout = wait.until { driver.find_element(:class, "header-menu-myaccount-signout-link") }
#DOESNT WORK ON SMALL WINDOW accountview = wait.until { driver.find_element(:class, "header-profile-welcome-link") }
#DOESNT WORK ON SMALL WINDOW accountview.click
#wait.until { driver.find_element(:class, "header-profile-welcome-link").click }
#accountview.click

# We are directly navigating here instead of clicking the button because the button changes depending on 
# the size of the browser window.
driver.get('https://sca.cdcstihl.biz/sca-dev-kilimanjaro/my_account.ssp?fragment=overview')
puts driver.title

purchasehistory = wait.until { driver.find_element(:class, "overview-home-orders-title-link") }
purchasehistory.click

# Now we are on the recent orders page, let's go to the open orders page
openorders = wait.until { driver.find_element(:class, "order-history-list-header-button-open") }
openorders.click

# On the open orders list, let's click the first order in the list for an example.
#firstitem = wait.until { driver.find_element(:class, "recordviews-actionable-title") }
#firstitem.click
#driver.navigate.back

# Wait until purchase history loads
wait.until { driver.find_element(:class, "recordviews-actionable-title") }

r=driver.find_elements(:class, "recordviews-actionable-title")
ponumbers = r.map {|x| x.attribute("innerText") }
podata = []

ponumbers.each do |ordernumber|
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
		tracking = nsec.css('.order-history-list-tracking-number-control-numbers-link')
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
		section_data << {shipped: is_shipped, shipdate: shipped_date, tracking: tracking, items: items}
	end

	podata << {order: ordernumber, date: date, sections: section_data}

	driver.navigate.back
end
File.write("sesca_out.json", podata.to_json)
driver.quit
