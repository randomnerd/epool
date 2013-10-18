crypto = require 'crypto'
util = require './util'

class Subscription
  constructor: (client, params, registry, diff = 32) ->
    @diff = diff
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
    @client.set_difficulty(diff)

  start: ->
    setTimeout (=> @setDiff(@diff)), 100
    [ @key, @extranonce1_hex, @extranonce2_size ]

module.exports = Subscription
