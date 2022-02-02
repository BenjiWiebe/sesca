#!/usr/bin/ruby
require 'json'
require 'pry'

spring_order = 'SO154761'
ignore_spring_order = true

bars = /^\d{4} \d{4}$/
units = /^[A-Z]{1,3} \d{2,3}/

obj = JSON.parse(File.read("sesca_out.json"), {symbolize_names: true})


unshipped_items = {}

obj.each do |order|
	if order[:order] == spring_order && ignore_spring_order
		puts "Ignoring spring order ##{spring_order}"
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

of_interest = unshipped_items.select do |item|
	item =~ bars || item =~ units
end

of_interest.sort.each do |k,v|
	puts "#{k}: #{v}" 
end
