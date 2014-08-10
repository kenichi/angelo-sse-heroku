require 'bundler'
Bundler.require :default
require 'angelo/tilt/erb'
require 'angelo/mustermann'
require File.join File.expand_path('..', __FILE__), 'chatdemo/redis'

module ChatDemo

  class App < Angelo::Base
    include Angelo::Tilt::ERB
    include Angelo::Mustermann

    # response for the post route
    #
    PUBLISHED = { status: 'published!' }

    # task subscribed to channel flags
    #
    @@subscriptions = {}

    # gimmie dat channel parameter as a symbol
    #
    before do
      @channel = params[:channel].to_sym rescue nil
    end

    # render the index page
    #
    get '/' do
      erb :index
    end

    # eventsource don't care
    #
    get '/assets/js/application.js' do
      content_type :js
      erb :application
    end

    # post a message to a channel without being subscribed to the channel!
    #
    post '/:channel' do
      content_type :json
      Redis.with {|r| r.publish Redis::CHANNEL_KEY % @channel, params[:msg].to_json}
      PUBLISHED
    end

    # subscribe to a channel
    #
    eventsource '/sse/:channel' do |es|

      # must specify a channel!
      #
      raise RequestError.new 'no channel specified!' unless @channel

      # add this eventsource to the channel stash
      #
      sses[@channel] << es

      # run the async subscription task unless it's already running
      #
      async :subscribe, @channel unless @@subscriptions[@channel]
    end



    # channel subscription task, defined on the reactor, called with
    # `async` above to begin piping all channel messages to all eventsources
    # subscribed to that channel (i.e. in that channel stash)
    #
    task :subscribe do |channel|

      # flag this channel as subscribed
      #
      @@subscriptions[channel] = true

      # catch a no-more-subscribed-sses event
      #
      catch :empty do

        # actually subscribe to the redis channel for the chat messages
        #
        Redis::new_redis.subscribe Redis::CHANNEL_KEY % channel do |on|
          on.message do |c, msg|

            # on every message, pipe it out to the connected eventsources
            #
            sses[channel].each {|es| es.write sse_message(msg)}

            # throw if there are no more connected eventsources
            #
            throw :empty if sses[channel].length == 0
          end
        end
      end

      # unflag this channel as subscribed before ending the task
      #
      @@subscriptions.delete channel
    end

  end
end

ChatDemo::App.run
