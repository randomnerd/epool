util = require './util'
bigint = require 'bigint'

class ShareLogger
  constructor: (algo, params) ->
    @roundstart = new Date()
    @algo = algo
    @params = params
    @hashrates = {}
    @stats = {}
    @shareBuffer = {}
    @modules = []
    for module, config of params?.modules?
      try
        @modules.push new (require("./sharelogger_modules/#{module}"))(config)
      catch e
        console.log e, e.stack

  logShare: (share) ->
    try
      @updateStats(share)
      for m in @modules
        m.logShare(share)
        m.logStats(@stats[share.username])

      console.log share.username, "stats: ", @stats[share.username]
      console.log(share) if share.upstream || share.upstreamReason
    catch e
      console.log e, e.stack

  getUserId: (username) -> username.split('.')?[0]

  calcRewards: (value) ->
    rewards = {}
    d1a = new bigint(0)
    d1a = d1a.add(s.d1a) for w, s of @stats
    for worker, stats of @stats
      r = new bigint(value).div(d1a).mul(stats.d1a)
      rewards[@getUserId(worker)] = r
    return rewards

  logBlock: (share, data, value) ->
    try
      unless block_data
        @log(share)
        return false

      share.upstream = true
      @logShare(share)

      block =
        time:       share.time
        diff:       data.difficulty
        hash:       share.block_hash
        value:      value
        height:     data.height
        finder:     @getUserId(share.username)
        rewards:    @calcRewards(value)
        timeSpent:  (new Date() - @roundstart) / 1000

      block.rewards = @calcRewards(value)

      m.logBlock(block) for m in @modules

      @roundstart = share.time
      console.log(block)
    catch e
      console.log e, e.stack

  updateStats: (share) ->
    stat = @stats[share.username] ||=
      diff:     0
      blocks:   0
      accepted: 0
      rejected: 0
      hashrate: 0

    stat.diff = share.diff_target
    stat.blocks++ if share.upstream

    if share.accepted
      stat.accepted++
    else
      stat.rejected++

    if share.accepted
      @updateBuffer(share)
      @updateHashrate(share.username)

  updateBuffer: (share) ->
    buf = @shareBuffer[share.username] ||= []
    @truncateBuffer(buf, 10) # FIXME: configurable time window
    buf.push [share.time, share.diff_target]

  updateHashrate: (name) ->
    buf = @shareBuffer[name]
    @stats[name].hashrate ||= 0
    return unless buf.length

    seconds = (buf[buf.length-1][0] - buf[0][0]) / 1000
    d1a = new bigint(0)
    d1a = d1a.add(s[1]) for s in buf
    @stats[name].d1a = d1a
    return unless seconds > 30
    @stats[name].hashrate = d1a.mul(65536).div(seconds).div(1000).toNumber()

  truncateBuffer: (buf, minutes) ->
    i = 0
    for s in buf
      break if util.minutesFrom(s[0]) > minutes
      i++

    buf.splice(i)

module.exports = ShareLogger
