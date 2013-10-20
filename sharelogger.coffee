util = require './util'
bigint = require 'bigint'

class ShareLogger
  constructor: (algo, params) ->
    @algo = algo
    @params = params
    @hashrates = {}
    @stats = {}
    @shareBuffer = {}

  log: (share) ->
    try
      @updateStats(share)
      console.log share.username, "stats: ", @stats[share.username]
      console.log(share) if share.upstream || share.upstreamResult
    catch e
      console.log e, e.stack

  updateStats: (share) ->
    stat = @stats[share.username] ||=
      blocks:   0
      accepted: 0
      rejected: 0
      hashrate: 0

    stat.blocks++   if share.upstream
    stat.accepted++ if share.accepted
    stat.rejected++ if share.rejected

    @updateBuffer(share)
    @updateHashrate(share.username)


  updateBuffer: (share) ->
    buf = @shareBuffer[share.username] ||= []
    @truncateBuffer(buf, 10)
    buf.push [share.time, share.diff_target]

  updateHashrate: (name) ->
    buf = @shareBuffer[name]
    @stats[name].hashrate ||= new bigint(0)
    return unless buf.length

    seconds = (buf[buf.length-1][0] - buf[0][0]) / 1000
    return unless seconds
    d1s = new bigint(0)
    d1s = d1s.add(s[1]) for s in buf
    @stats[name].hashrate = d1s.mul(65536).div(seconds).div(1000)

  truncateBuffer: (buf, minutes) ->
    i = 0
    for s in buf
      break if util.minutesFrom(s[0]) > minutes
      i++

    buf.splice(i)

module.exports = ShareLogger
