require 'sinatra'

get '/' do
  "Hello, world"
end

post '/checkin' do
	# Handle Foursquare checkins as they arrive
end