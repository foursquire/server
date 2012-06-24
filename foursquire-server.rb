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

class UrbanAirship
  include HTTParty
  basic_auth ENV['UA_KEY'], ENV['UA_MASTER_SECRET']
  base_uri 'https://go.urbanairship.com/api/push/'
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
	begin
		location = fq_user["checkins"]["items"][0]["venue"]["location"]
		epoch = fq_user["checkins"]["items"][0]["createdAt"]
	rescue
		# Maybe the user doesn’t have checkins yet.
	end

	name = fq_user["firstName"]; name += ' ' + fq_user["lastName"] unless fq_user["lastName"].nil?

	if location && epoch
		loc = {  'latitude' => location["lat"],
						'longitude' => location["lng"],
							'updated' => epoch }
	end

	# Query Usergrid /users/?ql=fq.id%3D=thatID
	ug_response = Usergrid.get '/users', :query => { 'ql' => "fq.id='#{fq_id}'" } 

	logger.info ug_response
	if ug_response.parsed_response["entities"].empty?
		# If no results
		logger.info "that user doesn't exist yet"
		#Usergrid.delete "/users/fq_#{fq_id}"

		response = Usergrid.post '/users', :body => {	'username' => "fq_#{fq_id}",
																										' email' => fq_user["contact"]["email"],
																									'location' => loc,
																											'name' => name,
																									 'picture' => 'https://is0.4sqi.net/userpix_thumbs' + fq_user["photo"]["suffix"],
																									      'fq' => fq_user }.to_json

		"Created a new user"
		#POST /users { username: fq_thatID, fq: the whole response.user, email: response.user.contact.email}
	else
		# If results
		logger.info "Found a user!"
		#PUT /users/UUID I received from the query above { fq: the whole response.user }
		response = Usergrid.put "/users", :query => { 'ql' => "fq.id='#{fq_id}'" },
																			:body  => { 			'fq' => fq_user,
																									'location' => loc,
																											'name' => name,
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

	content_type "application/json"
	response.body
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

get '/callback' do
	"All set! You can click the \"Done\" button below."
end

post '/challenge' do
	request.body.rewind
	req = JSON.parse request.body.read

	cr = Usergrid.get('/users', :query => { 'ql' => "fq.id='#{req["cr"]}'" }).parsed_response["entities"][0]
	ce = Usergrid.get('/users', :query => { 'ql' => "fq.id='#{req["ce"]}'" }).parsed_response["entities"][0]

	lngs = []; lats = []
	lngs << cr["location"]["longitude"]
	lats << cr["location"]["latitude"]
	lngs << ce["location"]["longitude"]
	lats << ce["location"]["latitude"]
	lngs = lngs.sort; lats = lats.sort

	# alpha = Math.sqrt( 	(cr["location"]["longitude"] - ce["location"]["longitude"])**2
	# 									+ (cr["location"]["latitude"]  - ce["location"]["latitude"] )**2 ) / 2

	# beta = 1.5*alpha
	# gamma = Math.sqrt( alpha**2 + beta**2 )

	# r = Math.sqrt( gamma**2 - a**2 - 2

	r = "%.9f" % Random.new.rand(lngs[0]..lngs[1])
	s = "%.9f" % Random.new.rand(lats[0]..lats[1])


	venue = HTTParty.get("https://api.foursquare.com/v2/venues/explore?ll=#{s},#{r}&section=food&limit=1&v=20120623&oauth_token=#{ENV['FQ_TOKEN']}").parsed_response["response"]["groups"][0]["items"][0]["venue"]

	challenge = { 'challenge' => { 		'venue_id' => venue["id"],
																	'venue_name' => venue["name"],
														  					'city' => venue["location"]["city"],
																		'latitude' => venue["location"]["lat"],
														 			 'longitude' => venue["location"]["lng"]	}	}
	Usergrid.put "/users/#{cr["uuid"]}", :body => challenge.to_json										 			 
	Usergrid.put "/users/#{ce["uuid"]}", :body => challenge.to_json
	
	UrbanAirship.post '/', :body => { 						"aps" => { "badge" => "+1", "alert" => "Get to #{venue['name']} quick!"},
																			"device_tokens" => [cr["ios"]["deviceToken"], ce["ios"]["deviceToken"]]}.to_json

	challenge.to_json
		 			 
end