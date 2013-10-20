util = require './util'
bigint = require 'bigint'

class ShareLogger
  constructor: (algo, params) ->
    @algo = algo
    @params = params
    @hashrates = {}
    @shareBuffer = {}

  log: (share) ->
    @updateBuffer(share)
    @updateHashrate(share.workername)
    console.log share, @hashrates[share.workername]

  updateBuffer: (share) ->
    buf = @shareBuffer[share.workername] ||= []
    @truncateBuffer(buf, 10)
    buf.push [share.time, share.diff_target]

  updateHashrate: (name) ->
    buf = @shareBuffer[name]
    @hashrates[name] ||= new bigint(0)
    return unless buf.length

    seconds = (buf[buf.length-1][0] - buf[0][0]) / 1000
    d1s = new bigint(0)
    d1s.add(s[1]) for s in buf
    console.log "hashrate calc: %s d1s in %s seconds", d1s, seconds
    switch @algo.toLowerCase()
      when 'scrypt'
        @hashrates[name] = d1s.mul(67108864)
      when 'sha256'
        @hashrates[name] = d1s.mul(4294967296)

  truncateBuffer: (buf, minutes) ->
    i = 0
    for s in buf
      console.log util.minutesFrom(s[0]), minutes
      break if util.minutesFrom(s[0]) < minutes
      i++

    buf.splice(i)

module.exports = ShareLogger
