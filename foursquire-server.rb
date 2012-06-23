require 'sinatra'

get '/' do
  "Hello, world"
end

post '/checkin' do
	# Handle Foursquare checkins as they arrive
	request.body.rewind
	logger.info request.media_type
	logger.info request.body.read
end