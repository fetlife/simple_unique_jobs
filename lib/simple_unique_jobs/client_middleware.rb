# frozen_string_literal: true

require "sidekiq"
require "murmurhash3"
require_relative "lock"

module SimpleUniqueJobs
  class ClientMiddleware
    include Sidekiq::ClientMiddleware

    def call(_worker, job, _queue, redis_pool, &)
      return yield unless job.key?('unique_for')

      set_unique_key(job)

      if job.key?('at')
        # this is a scheduled job, at the point of scheduling; note that down
        # as it'll be re-enqueued in the future
        job['unique_scheduled'] = true
        use_lock = true
      elsif job['unique_scheduled'] == true
        # this is a scheduled job, at the point of execution; we shouldn't
        # check locks, just this once
        job['unique_scheduled'] = false
        use_lock = false
      else
        # this is a normal job, non-scheduled or no-longer-scheduled job, at the point of enqueuing
        use_lock = true
      end

      use_lock ? Lock.new(job, redis_pool).if_enqueueable(&) : yield
    end

    private

    def set_unique_key(job)
      return if job.key?('unique_key')

      unique_args_fn = job.delete("unique_on") || ->(args) { args }
      unique_args = unique_args_fn.call(job['args']).to_s
      args_hash = MurmurHash3::V128.str_hexdigest(unique_args)
      job['unique_key'] = format('%<class>s:%<args_hash>s', class: job.fetch('class'), args_hash:)
    end
  end
end
