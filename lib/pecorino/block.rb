# frozen_string_literal: true

# Provides access to Pecorino blocks - same blocks which get set when a throttle triggers. The blocks
# are just keys in the data store which have an expiry value. This can be useful if you want to restrict
# access to a resource for an arbitrary timespan.
class Pecorino::Block
  # Sets a block for the given key. The block will also be seen by the Pecorino::Throttle with the same key
  #
  # @param key[String] the key to set the block for
  # @param block_for[Float] the number of seconds or a time interval to block for
  # @return [Time] the time when the block will be released
  def self.set!(key:, block_for:)
    Pecorino.adapter.set_block(key: key, block_for: block_for)
    Time.now + block_for
  end

  # Returns the time until a certain block is in effect
  #
  # @return [Time,nil] the time when the block will be released
  def self.blocked_until(key:)
    t = Pecorino.adapter.blocked_until(key: key)
    (t && t > Time.now) ? t : nil
  end
end
