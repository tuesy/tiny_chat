# cd chat
# bundle install
# bundle exec ruby web.rb -sv
# http://chat.x:9000/
require 'goliath'
require 'redis'
require 'json'
require 'rack/utils'
require 'debugger'
require 'goliath/rack/templates'

module Options
  def self.redis
    options = {driver: :synchrony}
    if ENV['REDISTOGO_URL']
      uri = URI.parse(ENV['REDISTOGO_URL'])
      options.merge!({host: uri.host, port: uri.port, password: uri.password})
    end
    options
  end
end

class Server < Goliath::API
  include Goliath::Rack::Templates      # render templated files from ./views
  use Goliath::Rack::Params

  @@redis = Redis.new(Options::redis)

  def payload
    "id: #{Time.now}\n" +
    "data: #{@message}" +
    "\r\n\n"
  end

  def response(env)
    case env['PATH_INFO']
    when '/'
      [200, {}, erb(:index)]
    when /^\/subscribe.*/
      EM.synchrony do
        @redis = Redis.new(Options::redis)
        channel = env["REQUEST_PATH"].sub(/^\/subscribe\//, '')
        puts channel
        @redis.subscribe(channel) do |on|
          on.message do |channel, message|
            @message = message
            env.stream_send(payload)
          end
        end
      end

      streaming_response(200, { 'Content-Type' => "text/event-stream" })
    when /.*/
      channel = env["REQUEST_PATH"][1..-1]
      message = Rack::Utils.escape_html(params["message"])
      @@redis.publish(channel, {sender: params["sender"], message: message}.to_json)
      [ 200, { }, [ ] ]
    else
      raise Goliath::Validation::NotFoundError
    end
  end

  def on_close(env)
    # @redis.disconnect if @redis && env['PATH_INFO'].match(/^\/subscribe.*/)
  end
end
