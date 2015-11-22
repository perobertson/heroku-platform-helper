require 'platform-api'
require 'rendezvous'
require 'colorize'

module HerokuHelper
  class App
    def initialize(api_key, app_name)
      @api_key = api_key
      @app_name = app_name
    end

    def deploy(branch:, worker: nil, clock: nil)
      remote = @app_name
      heroku = PlatformAPI.connect_oauth @api_key

      git_url = heroku.app.info(@app_name)['git_url']
      fail 'Cannot determine git url' if git_url.blank?

      # Fetch whats currently deployed
      system "[ \"$(git remote | grep -e ^#{remote})\" != '' ] && git remote rm #{remote}"
      unless system "git remote add #{remote} #{git_url}"
        fail "Could not add #{remote} remote #{git_url}"
      end
      unless system "git fetch #{remote} master"
        fail "Could not fetch master from #{remote}"
      end

      scale worker: 0, clock: 0
      maintenance true

      unless system "git push #{remote} #{branch}:master"
        fail "Failed to push branch(#{branch}) to remote(#{remote})"
      end

      migrate
      maintenance false
      scale worker: worker, clock: clock
    end

    def maintenance(enabled)
      heroku = PlatformAPI.connect_oauth @api_key
      if enabled
        puts "Enabling maintenance for #{@app_name}".cyan
      else
        puts "Disabling maintenance for #{@app_name}".cyan
      end
      heroku.app.update(@app_name, maintenance: enabled)
    end

    def migrate
      heroku = PlatformAPI.connect_oauth @api_key
      payload = {
        attach: true,
        command: 'rake db:migrate'
      }
      response = heroku.dyno.create(@app_name, payload)

      begin
        puts 'Running migrations'.cyan
        # set an activity timeout so it doesn't block forever
        Rendezvous.start(url: response['attach_url'], activity_timeout: 600)
      rescue => e
        log.error("Error capturing output for dyno\n#{e.message}")
      end
    end

    def scale(worker: nil, clock: nil)
      heroku = PlatformAPI.connect_oauth @api_key

      payload = {
        updates: []
      }

      formations = heroku.formation.list(@app_name)
      formations.each do |formation|
        size = formation['size']
        if !worker.nil? && formation['type'] == 'worker'
          if formation['quantity'] != worker
            payload[:updates] << {
              process: 'worker',
              quantity: worker,
              size: size
            }
            puts "Scaling worker to #{worker}".cyan
          else
            puts "Worker is already scaled to #{worker}".yellow
          end
        elsif !clock.nil? && formation['type'] == 'clock'
          if formation['quantity'] != clock
            payload[:updates] << {
              process: 'clock',
              quantity: clock,
              size: size
            }
            puts "Scaling clock to #{clock}".cyan
          else
            puts "Clock is already scaled to #{clock}".yellow
          end
        end
      end

      if payload[:updates].empty?
        puts 'Warning: nothing to scale. Please check your configurations'.yellow
      else
        if payload[:updates].map { |u| u[:size] }.uniq.include? 'Free'
          puts 'Warning: you can only run 2 dynos on the free tier'.yellow
          updates = payload[:updates].sort { |a, b| a[:quantity] <=> b[:quantity] }
          updates.each do |update|
            type = update[:process]
            quantity = update[:quantity]
            heroku.formation.update(@app_name, type, quantity: quantity)
          end
        else
          heroku.formation.batch_update(@app_name, payload)
        end
      end
    end
  end
end
