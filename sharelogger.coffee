util = require './util'
bignum = require 'bignum'
_ = require 'underscore'

class ShareLogger
  constructor: (algo, params, rpc) ->
    @roundstart = new Date()
    @algo = algo
    @params = params
    @hashrates = {}
    @stats = {}
    @shareBuffer = {}
    @modules = []
    for module, config of params?.modules
      try
        @modules.push new (require("./sharelogger_modules/#{module}"))(config, rpc)
      catch e
        console.log e, e.stack

  logShare: (share) ->
    try
      @updateStats(share)
      for m in @modules
        m.logShare(share)
        m.logStats(share.username, @stats[share.username])
    catch e
      console.log e, e.stack

  getUserId: (username) -> username.split('.')?[0]

  calcRewards: ->
    rewards = {}
    # d1a = 0
    # d1a += s.d1a for w, s of @stats
    # for worker, stats of @stats
    #   rewards[@getUserId(worker)] ||= 0
    #   rewards[@getUserId(worker)] += stats.d1a / d1a

    total_d1a = 0
    tmp = {}
    for worker, shares of @shareBuffer
      n = _.reduce(shares, ((m, n) => m+n[1]), 0)
      total_d1a += n
      tmp[@getUserId(worker)] ||= 0
      tmp[@getUserId(worker)] += n

    for user, d1a of tmp
      rewards[user] = d1a / total_d1a

    return rewards

  logBlock: (share, data) ->
    try
      unless data
        @log(share)
        return false

      share.upstream = true
      @logShare(share)

      block =
        time:       share.time
        diff:       data.difficulty
        hash:       share.block_hash
        txid:       data.tx[0]
        height:     data.height
        finder:     @getUserId(share.username)
        rewards:    @calcRewards()
        timeSpent:  (new Date() - @roundstart) / 1000

      m.logBlock(block) for m in @modules

      @roundstart = share.time
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
    @truncateBuffer(buf, @params.shareTimeFrame) # FIXME: configurable time window
    buf.push [share.time, share.diff_target]

  updateHashrate: (name) ->
    buf = @shareBuffer[name]
    @stats[name].hashrate ||= 0
    return unless buf.length

    seconds = (buf[buf.length-1][0] - buf[0][0]) / 1000
    d1a = 0
    d1a += s[1] for s in buf
    @stats[name].d1a = d1a
    return unless seconds > 30
    switch @algo
      when 'scrypt'
        dmulti = 67108864
        hmulti = 1000000
      when 'sha256'
        dmulti = 4294967296
        hmulti = 1000
    @stats[name].hashrate = new bignum(d1a).mul(dmulti).div(seconds).div(hmulti).toNumber()

  truncateBuffer: (buf, minutes) ->
    i = 0
    for s in buf
      break if util.minutesFrom(s[0]) < minutes
      i++

    buf.splice(0,i)

module.exports = ShareLogger
