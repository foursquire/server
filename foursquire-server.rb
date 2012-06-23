require 'sinatra'
require 'open-uri'
require 'json/ext'

get '/' do
  "Hello, world"
end

post '/checkin' do
	# Handle Foursquare checkins as they arrive

	request.body.rewind
	checkin = JSON.parse URI.decode request.body.read.split('checkin=').last.split('&user').first
	logger.info checkin["venue"]["location"]["lat"].to_s + ' / ' + checkin["venue"]["location"]["lng"].to_s
end