# Pecorino

Pecorino is a rate limiter based on the concept of leaky buckets, or more specifically - based on the [generic cell rate](https://brandur.org/rate-limiting) algorithm. It uses your DB as the storage backend for the throttles. It is compact, easy to install, and does not require additional infrastructure. The approach used by Pecorino has been previously used by [prorate](https://github.com/WeTransfer/prorate) with Redis, and that approach has proven itself.

Pecorino is designed to integrate seamlessly into any Rails application, and will use either:

* A memory store (good enough if you have just 1 process)
* A PostgreSQL or SQLite database (at the moment there is no MySQL support, we would be delighted if you could add it)
* A Redis instance

If you would like to know more about the leaky bucket algorithm: [this article](http://live.julik.nl/2022/08/the-unreasonable-effectiveness-of-leaky-buckets) or the [Wikipedia article](https://en.wikipedia.org/wiki/Leaky_bucket) are both good starting points. [This Wikipedia article](https://en.wikipedia.org/wiki/Generic_cell_rate_algorithm) describes the generic cell rate algorithm in more detail as well.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'pecorino'
```

And then execute:

    $ bundle install
    $ bin/rails g pecorino:install
    $ bin/rails db:migrate

## Usage

Once the installation is done you can use Pecorino to start defining your throttles. Imagine you have a resource called `vault` and you want to limit the number of updates to it to 5 per second. To achieve that, instantiate a new `Throttle` in your controller or job code, and then trigger it using `Throttle#request!`. A call to `request!` registers 1 token getting added to the bucket. If the bucket would overspill (your request would make it overflow), or the throttle is currently in "block" mode (has recently been triggered), a `Pecorino::Throttle::Throttled` exception will be raised.

We call this pattern **prefix usage** - apply throttle before allowing the action to proceed. This is more secure than registering an action after it has taken place.

```ruby
throttle = Pecorino::Throttle.new(key: "password-attempts-#{request.ip}", over_time: 1.minute, capacity: 5, block_for: 30.minutes)
throttle.request!
```
In a Rails controller you can then rescue from this exception to render the appropriate response:

```ruby
rescue_from Pecorino::Throttle::Throttled do |e|
  response.set_header('Retry-After', e.retry_after.to_s)
  render nothing: true, status: 429
end
```

and in a Rack application you can rescue inline:

```ruby
def call(env)
  # ...your code
rescue Pecorino::Throttle::Throttled => e
  [429, {"Retry-After" => e.retry_after.to_s}, []]
end
```

The exception has an attribute called `retry_after` which you can use to render the appropriate 429 response.

Although this approach might be susceptible to race conditions, you can interrogate your throttle before potentially causing an exception - and display an appropriate error message if the throttle would trigger anyway:

```ruby
return render :capacity_exceeded unless throttle.able_to_accept?
```

If you are dealing with a metered resource (like throughput, money, amount of storage...) you can supply the number of tokens to either `request!` or `able_to_accept?` to indicate the desired top-up of the leaky bucket. For example, if you are maintaining user wallets and want to ensure no more than 100 dollars may be taken from the wallet within a certain amount of time, you can do it like so:

```ruby
throttle = Pecorino::Throttle.new(key: "wallet_t_#{current_user.id}", over_time_: 1.hour, capacity: 100, block_for: 3.hours)
throttle.request!(20) # Attempt to withdraw 20 dollars
throttle.request!(20) # Attempt to withdraw 20 dollars more
throttle.request!(20) # Attempt to withdraw 20 dollars more
throttle.request!(20) # Attempt to withdraw 20 dollars more
throttle.request!(20) # Attempt to withdraw 20 dollars more
throttle.request!(2) # Attempt to withdraw 2 dollars more, will raise `Throttled` and block withdrawals for 3 hours
```

## Performing a block only if it would be allowed by the throttle

You can use Pecorino to avoid nuisance alerting - use it to limit the alert rate:

```ruby
alert_nuisance_t = Pecorino::Throttle.new(key: "disk-full-alert", over_time_: 2.hours, capacity: 1, block_for: 2.hours)
alert_nuisance_t.throttled do
  Slack.alerts.deliver("Disk is full again! please investigate!")
end
```

This will not raise any exceptions. The `throttled` method performs **prefix throttling** to prevent multiple callers hitting the throttle at the same time, so it is guaranteed to be atomic.

## Postfix topup of the throttle

In addition to use case where you would want to trigger the throttle before performing an action, there are legitimate use cases where you actually want to use the throttle as a _meter_ instead, measuring the effect of an action which has already been permitted – and then only make it trigger on a subsequent action. This **postfix usage** is less secure, but it allows for a different sequencing of calls. Imagine you want to implement the popular [circuit breaker pattern](https://dzone.com/articles/introduction-to-the-circuit-breaker-pattern) where all your nodes are able to share the error rate information between them. Pecorino gives you all the tools to implement a binary state circuit breaker (open or closed) based on an error rate. Imagine you want to stop sending requests if the service you are calling raises `Timeout::Error` frequently. Then your call to the service could look like this:

```ruby
begin
  error_rate_throttle = Pecorino::Throttle.new("some-fancy-ai-api-errors", capacity: 10, over_time: 30.seconds, block_for: 120.seconds)

  if error_rate_throttle.able_to_accept? # See whether adding 1 request will overflow the error rate
    fancy_ai_api.post_chat_message("Imagine I am a rocket scientist on a moonbase. Invent me...")
  else
    raise "The error rate for fancy_ai_api has been exceeded"
  end
rescue Timeout::Error
  error_rate_throttle.request(1) # use bang-less method since we do not need the Throttled exception
  raise
end
```

This way, every time there is an error on the "fancy AI service" the throttle will be triggered, and if it overflows - a subsequent request will be blocked.

## A note on database transactions

Pecorino uses your main database. When calling the `Throttle` or `LeakyBucket` objects, SQL queries will be performed by Pecorino and those queries may result in changes to data. If you are currently inside a database transaction, your bucket topups or set blocks may get reverted. For example, imagine you have a controller like this:

```ruby
class WalletController < ApplicationController
  rescue_from Pecorino::Throttle::Throttled do |e|
    response.set_header('Retry-After', e.retry_after.to_s)
    render nothing: true, status: 429
  end

  def withdraw
     Wallet.transaction do
       t = Pecorino::Throttle.new("wallet_#{current_user.id}_max_withdrawal", capacity: 200_00, over_time: 5.minutes)
       t.request!(10_00)
       current_user.wallet.withdraw(Money.new(10, "EUR"))
     end
  end
end
```

what will happen is that even though the `withdraw()` call is not going to be performed, the increment of the throttle will not either, because the exception will result in a `ROLLBACK`.

If you need to use Pecorino in combination with transactions, you will need to design with that in mind. Either call `Throttle` before entering the `transaction do`:

```ruby
def withdraw
  t = Pecorino::Throttle.new("wallet_#{current_user.id}_max_withdrawal", capacity: 200_00, over_time: 5.minutes)
  t.request!(10_00)
  Wallet.transaction do
    current_user.wallet.withdraw(Money.new(10, "EUR"))
  end
end
```

or use the `request()` method instead to still commit:

```ruby
def withdraw
  Wallet.transaction do
    t = Pecorino::Throttle.new("wallet_#{current_user.id}_max_withdrawal", capacity: 200_00, over_time: 5.minutes)
    throttle_state = t.request(10_00)
    return render(nothing: true, status: 429) if throttle_state.blocked?

    current_user.wallet.withdraw(Money.new(10, "EUR"))
  end
end
```

Note also that this behaviour might be desirable for your use case (that the throttle and the data update together in
a transactional manner) – it just helps to be aware of it.

## Using just the leaky bucket

Sometimes you don't want to use a throttle, but you want to track the amount added to the leaky bucket over time. A lower-level abstraction is available for that purpose in the form of the `LeakyBucket` class. It will not raise any exceptions and will not install blocks, but will permit you to track a bucket's state over time:


```ruby
b = Pecorino::LeakyBucket.new(key: "some_b", capacity: 100, leak_rate: 1)
b.fillup(2) #=> Pecorino::LeakyBucket::State(full?: false, level: 2.0)
sleep 0.2
b.state #=> Pecorino::LeakyBucket::State(full?: false, level: 1.8)
```

Check out the inline YARD documentation for more options. Do take note of the differences between `fillup()` and `fillup_conditionally` as you
might want to pick one or the other depending on your use case.

## Cleaning out stale buckets and blocks from the database

We recommend running the following bit of code every couple of hours (via cron or similar) to delete the stale blocks and leaky buckets from the system:

```ruby
Pecorino.prune!
```

## Testing your application

The Pecorino buckets and blocks are stateful. If you are not running tests with a transaction rollback, the rate limiters that got hit in a test case may interfere with other test cases you are running. Normally you will not notice this (if you are using the same database as the rest of your models), but we recommend adding this section to your global test case setup:

```ruby
setup do
  # Delete all transient records
  ActiveRecord::Base.connection.execute("TRUNCATE TABLE pecorino_blocks")
  ActiveRecord::Base.connection.execute("TRUNCATE TABLE pecorino_leaky_buckets")
end
```

If you are using Redis, you may want to ensure it gets truncated/reset for every test case - or that parallel test case runners [each use a separate Redis database.](https://redis.io/docs/latest/commands/select/)

## Using cached throttles

If a throttle is triggered, Pecorino sets a "block" record for that throttle key. Any request to that throttle will fail until the block is lifted. If you are getting hammered by requests which are getting throttled, it might be a good idea to install a caching layer which will respond with a "rate limit exceeded" error even before hitting your database - until the moment when the block would be lifted. You can use any [ActiveSupport::Cache::Store](https://api.rubyonrails.org/classes/ActiveSupport/Cache/Store.html) to store your blocks. If you have a fast Rails cache configured, create a wrapped throttle:

```ruby
throttle = Pecorino::Throttle.new(key: "ip-#{request.ip}", capacity: 10, over_time: 2.seconds, block_for: 2.minutes)
cached_throttle = Pecorino::CachedThrottle.new(Rails.cache, throttle)
cached_throttle.request!
```

Note that the idea of using a cache store here is to avoid hitting the database when the block for your throttle is in effect. Therefore, if you are using something like [solid_cache](https://github.com/rails/solid_cache) you will be hitting the database regardless! A better approach is to have a [MemoryStore](https://api.rubyonrails.org/classes/ActiveSupport/Cache/MemoryStore.html) just for throttles - it will be local to your Rails process. This will avoid a database roundtrip once the process knows a particular throttle is being blocked at the moment:

```ruby
# in application.rb
config.pecorino_throttle_cache = ActiveSupport::Cache::MemoryStore.new

# in your controller

throttle = Pecorino::Throttle.new(key: "ip-#{request.ip}", capacity: 10, over_time: 2.seconds, block_for: 2.minutes)
cached_throttle = Pecorino::CachedThrottle.new(Rails.application.config.pecorino_throttle_cache, throttle)
cached_throttle.request!
```

## Using unlogged tables for reduced replication load (PostgreSQL)

Throttles and leaky buckets are transient resources. If you are using Postgres replication, it might be prudent to set the Pecorino tables to `UNLOGGED` which will exclude them from replication - and save you bandwidth and storage on your RR. To do so, add the following statements to your migration:

```ruby
ActiveRecord::Base.connection.execute("ALTER TABLE pecorino_leaky_buckets SET UNLOGGED")
ActiveRecord::Base.connection.execute("ALTER TABLE pecorino_blocks SET UNLOGGED")
```

## Development

After checking out the repo, run `bundle`. Then, run `rake test` to run the tests.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/cheddar-me/pecorino. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/cheddar-me/pecorino/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Pecorino project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/cheddar-me/pecorino/blob/main/CODE_OF_CONDUCT.md).
