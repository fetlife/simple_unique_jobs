require 'sidekiq'
require_relative 'lock'

module SimpleUniqueJobs
  class ClientMiddleware
    include Sidekiq::ClientMiddleware

    def call(_worker, job, _queue, redis_pool)
      # $stderr.puts "ClientMiddleware: #{job.slice('unique_for', 'class', 'args').inspect}"
      Lock.new(job, redis_pool).if_enqueueable { yield }
    end
  end
end
