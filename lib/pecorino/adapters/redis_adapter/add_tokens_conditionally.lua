-- Single threaded Leaky Bucket implementation (without blocking).
-- args: key_base, leak_rate, bucket_ttl, fillup. To just verify the state of the bucket leak_rate of 0 may be passed.
-- returns: the leve of the bucket in number of tokens

-- this is required to be able to use TIME and writes; basically it lifts the script into IO
redis.replicate_commands()

-- Redis documentation recommends passing the keys separately so that Redis
-- can - in the future - verify that they live on the same shard of a cluster, and
-- raise an error if they are not. As far as can be understood this functionality is not
-- yet present, but if we can make a little effort to make ourselves more future proof
-- we should.
local bucket_level_key = KEYS[1]
local last_updated_key = KEYS[2]

local leak_rate = tonumber(ARGV[1])
local fillup = tonumber(ARGV[2]) -- How many tokens this call adds to the bucket.
local bucket_capacity = tonumber(ARGV[3]) -- How many tokens is the bucket allowed to contain
local conditional_fillup = tonumber(ARGV[4]) -- Whether to fillup conditionally

-- Compute the key TTL for the bucket. We are interested in how long it takes the bucket
-- to leak all the way to 0, as this is the time when the values stay relevant. We pad with 1 second
-- to have a little cushion.
local key_lifetime = math.ceil((bucket_capacity / leak_rate) + 1)

-- Take a timestamp
local redis_time = redis.call("TIME") -- Array of [seconds, microseconds]
local now = tonumber(redis_time[1]) + (tonumber(redis_time[2]) / 1000000)

-- get current bucket level. The throttle key might not exist yet in which
-- case we default to 0
local bucket_level = tonumber(redis.call("GET", bucket_level_key)) or 0

-- ...and then perform the leaky bucket fillup/leak. We need to do this also when the bucket has
-- just been created because the initial fillup to add might be so high that it will
-- immediately overflow the bucket and trigger the throttle, on the first call.
local last_updated = tonumber(redis.call("GET", last_updated_key)) or now -- use sensible default of 'now' if the key does not exist

-- Subtract the number of tokens leaked since last call
local dt = now - last_updated
local bucket_level_after_leaking = math.max(0, math.min(bucket_level - (leak_rate * dt), bucket_capacity))
local bucket_level_after_fillup = bucket_level_after_leaking + fillup
local did_accept = 0

-- Figure out whether the fillup would overflow the bucket
if conditional_fillup and bucket_level_after_fillup > bucket_capacity then
  local at_capacity = bucket_level_after_leaking >= bucket_capacity
  -- See below about string return
  return {string.format("%.9f", bucket_level_after_leaking), at_capacity, did_accept}
end

-- and _then_ and add the tokens we fillup with. Cap the value to be 0 < capacity
local new_bucket_level = math.max(0, math.min(bucket_capacity, bucket_level_after_fillup))

-- Since we return a floating point number string-formatted even if the bucket is full we
-- have some loss of precision in the formatting, even if the bucket was actually full.
-- This bit of information is useful to preserve.
local at_capacity = 0
if new_bucket_level == bucket_capacity then
  at_capacity = 1
end

did_accept = 1

-- If both the initial level was 0, and the level after putting tokens in is 0 we
-- can avoid setting keys in Redis at all as this was only a level check.
if new_bucket_level == 0 and bucket_level == 0 then
  return {"0.0", at_capacity, did_accept}
end

-- Save the new bucket level
redis.call("SETEX", bucket_level_key, key_lifetime, new_bucket_level)

-- Record when we updated the bucket so that the amount of tokens leaked
-- can be correctly determined on the next invocation
redis.call("SETEX", last_updated_key, key_lifetime, now)

-- Most Redis adapters when used with the Lua interface truncate floats
-- to integers (at least in Python that is documented to be the case in
-- the Redis ebook here
-- https://redislabs.com/ebook/part-3-next-steps/chapter-11-scripting-redis-with-lua/11-1-adding-functionality-without-writing-c
-- We need access to the bucket level as a float value since our leak rate might as well be floating point, and to achieve that
-- we can go two ways. We can turn the float into a Lua string, and then parse it on the other side, or we can convert it to
-- a tuple of two integer values - one for the integer component and one for fraction.
-- Now, the unpleasant aspect is that when we do this we will lose precision - the number is not going to be
-- exactly equal to capacity, thus we lose the bit of information which tells us whether we filled up the bucket or not.
-- Also since the only moment we can register whether the bucket is above capacity is now - in this script, since
-- by the next call some tokens will have leaked.
return {string.format("%.9f", new_bucket_level), at_capacity, did_accept}
