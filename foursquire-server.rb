require 'sinatra'
require 'open-uri'
require 'json/ext'
require 'httparty'

get '/' do
  ENV['HOST']
end

class Usergrid
  include HTTParty
  base_uri 'https://usergrid-prod-api-v2.elasticbeanstalk.com/Foursquire/foursquire2'
  debug_output $stderr
  #default_params :output => 'json'
  format :json
  headers "Content-Type" => "application/json"
end

get '/login/:token' do
	# Receive a token as a query string 
	token = params[:token]

	# Call foursquare
	fq_response = HTTParty.get "https://api.foursquare.com/v2/users/self?oauth_token=#{token}&v=20120623"

	# Receive the JSON, store the request.body => response.user.id
	fq_user = fq_response.parsed_response["response"]["user"]; fq_id = fq_user["id"]
	location = fq_user["checkins"]["items"][0]["venue"]["location"]
	epoch = fq_user["checkins"]["items"][0]["createdAt"]

	# Query Usergrid /users/?ql=fq.id%3D=thatID
	ug_response = Usergrid.get '/users', :query => { 'ql' => "fq.id='#{fq_id}'" } 

	logger.info ug_response
	if ug_response.parsed_response["entities"].empty?
		# If no results
		logger.info "that user doesn't exist yet"
		Usergrid.delete "/users/fq_#{fq_id}"
		response = Usergrid.post '/users', :body => {	'username' => "fq_#{fq_id}",
																										' email' => fq_user["contact"]["email"],
																									'location' => {  'latitude' => location["lat"],
																																	'longitude' => location["lng"],
																																	  'updated' => epoch},
																											'name' => fq_user["firstName"] + ' ' + fq_user["lastName"],
																									 'picture' => 'https://is0.4sqi.net/userpix_thumbs' + fq_user["photo"]["suffix"],
																									      'fq' => fq_user }.to_json

		"Created a new user"
		#POST /users { username: fq_thatID, fq: the whole response.user, email: response.user.contact.email}
	else
		# If results
		logger.info "Found a user!"
		#PUT /users/UUID I received from the query above { fq: the whole response.user }
		response = Usergrid.put "/users", :query => { 'ql' => "fq.id='#{fq_id}'" },
																			:body  => { 'fq' => fq_user,
																									'location' => {  'latitude' => location["lat"],
																																	'longitude' => location["lng"],
																																	  'updated' => epoch },
																								'name' => fq_user["firstName"] + ' ' + fq_user["lastName"],
																						 'picture' => 'https://is0.4sqi.net/userpix_thumbs' + fq_user["photo"]["suffix"]
																								}.to_json

		"Updated an existing user"
	end

	if ENV['HOST'] == 'localhost' # Get recent checkins from friends to populate the Usergrid graph
		recents = HTTParty.get("https://api.foursquare.com/v2/checkins/recent?oauth_token=#{token}&v=20120623").parsed_response["response"]["recent"]
		friends = []
		ids_seen = []
		recents.each do |recent|
			next if ids_seen.include? recent["user"]["id"]
			begin
				Usergrid.post '/users', :body => {	'username' => "fq_#{recent["user"]["id"]}",
																						'location' => {  'latitude' => recent["venue"]["location"]["lat"],
																														'longitude' => recent["venue"]["location"]["lng"],
												 																			'updated' => recent["createdAt"]},
																								'name' => recent["user"]["firstName"] + ' ' + recent["user"]["lastName"],
																						 'picture' => 'https://is0.4sqi.net/userpix_thumbs' + recent["user"]["photo"]["suffix"],
																									'fq' => recent["user"] }.to_json
			rescue TypeError
				logger.error "A friend creation failed"
			ensure
				ids_seen << recent["user"]["id"]
			end
		end
	end

end

post '/checkin' do
	# Handle Foursquare checkins as they arrive

	request.body.rewind
	checkin = JSON.parse URI.decode request.body.read.split('checkin=').last.split('&user').first
	request.body.rewind
	user 		= JSON.parse URI.decode request.body.read.split('&user=').last.split('&secret').first
	# logger.info checkin["venue"]["location"]["lat"].to_s + ' / ' + checkin["venue"]["location"]["lng"].to_s


	Usergrid.put "/users", :query => 	{ 'ql' => "fq.id='#{user["id"]}'" },
													:body => 	{ 'location' => {	 'latitude' => checkin["venue"]["location"]["lat"],
																											'longitude' => checkin["venue"]["location"]["lng"],
																												'updated' => checkin["createdAt"] }
																		}.to_json
	#PUT /users?ql=fq.id=thatID {location:{latitute: lat , longitude: lng}}
end

post '/challenge' do
	request.body.rewind

	challenge = JSON.parse request.body.read

end