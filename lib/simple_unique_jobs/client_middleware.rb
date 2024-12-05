# frozen_string_literal: true

require "sidekiq"
require "murmurhash3"
require_relative "lock"

module SimpleUniqueJobs
  class ClientMiddleware
    include Sidekiq::ClientMiddleware

    def call(_worker, job, _queue, redis_pool, &)
      set_unique_key(job)
      Lock.new(job, redis_pool).if_enqueueable(&)
    end

    private

    def set_unique_key(job)
      return unless job.key?('unique_for')
      return if job.key?('unique_key')

      unique_args_fn = job.delete("unique_on") || ->(args) { args }
      unique_args = unique_args_fn.call(job['args']).to_s
      args_hash = MurmurHash3::V128.str_hexdigest(unique_args)
      job['unique_key'] = format('%s:%s', job.fetch('class'), args_hash)
    end

    def job_unique_args(job)
      unique_args_fn = job.delete("unique_on") || ->(args) { args }
      unique_args_fn.call(job['args']).to_s
    end
  end
end
