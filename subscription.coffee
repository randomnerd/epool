crypto = require 'crypto'
util = require './util'

class Subscription
  constructor: (client, params, registry, diff = 32) ->
    @submits = 0
    @diff = diff
    @lastDiffUpdate = null
    @session = {}
    @params = params
    @client = client
    @id = client.id
    @key = @getKey(@id)
    @client.subscription = @
    @registry = registry
    @extranonce1_bin = registry.getNewExtranonce1()
    @extranonce1_hex = util.hexlify(@extranonce1_bin)
    @extranonce2_size = registry.extranonce2_size

  getKey: (id) ->
    hash = crypto.createHash('md5')
    hash.update(@id)
    hash.digest('hex')

  setDiff: (diff) ->
    @diff = diff
    @lastDiffUpdate = new Date()
    @client.set_difficulty(diff)

  sharesPerMin: -> @submits / @minsSinceLastDiffUpd()
  minsSinceLastDiffUpd: -> util.minutesFrom(@lastDiffUpdate)

  start: ->
    setTimeout (=> @setDiff(@diff)), 100
    [ @key, @extranonce1_hex, @extranonce2_size ]

  updateDiff: (min, max, perMin, window) ->
    @submits++
    return unless @minsSinceLastDiffUpd() >= window
    newDiff = Math.max(min, Math.round(@sharesPerMin() / perMin * @diff))
    return if newDiff == @diff
    @submits = 0
    @setDiff(Math.min(newDiff, max))

module.exports = Subscription
