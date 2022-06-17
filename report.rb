#!/usr/bin/ruby
require 'json'
require 'pry'


# This is the array of order numbers (prefixed with SO to match SCA) to be excluded from the back-order report
ignore_orders = ['SO154761']
units_bars_only = false
html_output = true

datafile = "sesca_out.json"

bars = /^\d{4} \d{4}$/
units = /^[A-Z]{1,3} \d{2,3}/

obj = JSON.parse(File.read(datafile), {symbolize_names: true})


unshipped_items = {}

obj.each do |order|
	if ignore_orders.include? order[:order]
		puts "Ignoring order ##{order[:order]}" unless html_output
		next
	end
	order[:sections].each do |section|
		next if section[:shipped]
		items = section[:items]
		items.each do |item|
			partno = item[:partno]
			qty = item[:qty]
			unshipped_items[partno] = 0 unless unshipped_items[partno]
			unshipped_items[partno] = qty + unshipped_items[partno]
		end
	end
end

if units_bars_only
	of_interest = unshipped_items.select do |item|
		item =~ bars || item =~ units
	end
else
	of_interest = unshipped_items
end

last_update_time = File.mtime(datafile)

if html_output
	print '<!DOCTYPE html><html><head><link rel="stylesheet" href="report.css" /><title>SCA on-order report</title></head><body><table><tbody>'
	print '<tr><th>Quantity</th><th>Model/part number</th></tr>'
	of_interest.sort.each do |k,v|
		print "<tr><td>#{v}</td><td>#{k}</td>"
	end
	print '</tbody></table>'
	timeago = ((Time.now - last_update_time) / 60 / 60).floor
	word='hour'
	if timeago > 24
		word='day'
		timeago /= 24
	end
	ftime = last_update_time.strftime('%b %-d, %Y')
	print "<a>Last updated: #{timeago} #{word}#{timeago != 1 ? 's' : ''} ago (#{ftime})</a>"
	print '</body></html>'
else
	of_interest.sort.each do |k,v|
		puts "#{v} - #{k}" 
	end
end
