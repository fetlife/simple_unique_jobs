require 'sidekiq'
require_relative 'lock'

module SimpleUniqueJobs
  class ServerMiddleware
    include Sidekiq::ServerMiddleware

    def call(_job_instance, job_payload, _queue)
      lock = Lock.new(job_payload, Sidekiq.redis_pool)

      lock.unlock_enqueue
      lock.if_runnable { yield }
    end
  end
end
