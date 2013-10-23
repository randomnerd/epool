mg = require('mongoose')
Random = require './meteor_random'
ShareLogger = require('../../sharelogger')
async = require 'async'
_ = require 'underscore'

CXBlock = mg.model 'block', mg.Schema
  _id:    String
  cat:    String
  acc:    Boolean
  paid:   Boolean
  conf:   Number
  txid:   String
  hash:   String
  number: Number
  reward: Number
  currId: String
  finder: String
  dbTime: Date
  time: Date
  stratum: {type: Boolean, default: true}

CXHashrate = mg.model 'hashrate', mg.Schema
  _id:      String
  name:     String
  currId:   String
  userId:   String
  wrkName:  String
  hashrate: Number

CXBlockStat = mg.model 'block_stat', mg.Schema
  _id:      String
  time:     Date
  paid:     Boolean
  blkId:    String
  currId:   String
  userId:   String
  reward:   Number
  payTime:  Boolean

CXUserShema = mg.Schema
  _id: String
  emails: [{address: String, verified: Boolean}]
  profile:
    nickname: String

CXCurrency = mg.model 'currency', mg.Schema(
  { _id: String, miningFee: Number }
), 'currencies'

CXUserShema.methods.nickname = ->
  nickname = @profile?.nickname
  nickname ||= @emails[0].address.replace(/@.*/, '')

CXUser = mg.model 'user', CXUserShema

class CoinExShareLogger extends ShareLogger
  constructor: (params, rpc) ->
    @rpc = rpc
    @params = params
    @db = null
    @connected = false
    @connect()
    @currId = params.currencyId
    @flushInterval = params.flushInterval || 10
    @poolFee = 0
    @buffer =
      lastFlush: null
      stats:  {}
      blocks: []

  connect: ->
    console.log 'CoinEX sharelogger - connecting'
    @db = mg.connect(@params.dbString)
    @db.connection.on 'open',  => @connStatus(true)
    @db.connection.on 'error', => @connStatus(false)
    @db.connection.on 'close', => @connStatus(false)

  connStatus: (c) ->
    @connected = c
    console.log 'CoinEX sharelogger', (if c then 'connected' else 'disconnected')
    unless c
      setTimeout (=> @connect()), 100

  logShare: (share) -> true
  logBlock: (block) ->
    @buffer.blocks.push block
    @flush()

  logStats: (name, stats) ->
    return unless name.split('.').length == 2
    @buffer.stats[name] = stats
    @flush()

  flush: (force = false) ->
    force = true unless @lastFlush
    return unless force || (new Date() - @lastFlush) / 1000 >= @flushInterval
    return unless @connected

    try
      @saveStats(@buffer.stats)
      @saveBlock(block) for block in @buffer.blocks
      @buffer.stats = {}
      @buffer.blocks = []
      @lastFlush = new Date()
    catch e
      console.log e, e.stack

  saveHrate: (userId, name, wrkName, hashrate) ->
    console.log name, wrkName, hashrate
    sel =
      currId: @currId
      userId: userId
      wrkName: wrkName

    CXHashrate.findOne sel, (e, rec) =>
      if !e && rec = new CXHashrate(rec)
        rec.hashrate = hashrate
        rec.name = name
        rec.save()
      else
        rec = new CXHashrate
          _id:      Random.id()
          name:     name
          currId:   @currId
          userId:   userId
          wrkName:  wrkName
          hashrate: hashrate
        rec.save()

  updateTotalHrate: (userId, cb) ->
    sel = {currId: @currId, userId: userId, wrkName: {$ne: '__total__'}}
    CXHashrate.find sel, (e, recs) =>
      return if e || !recs.length
      hrate = 0
      name = recs[0].name
      hrate += r.hashrate for r in recs
      @saveHrate(userId, name, '__total__', hrate)
      cb(null, true) if cb

  saveStats: (stats) ->
    users = []

    updHrate = (data, cbx) =>
      [worker, stats] = data
      [userId, wrkName] = worker.split('.')
      users.push(userId) unless _.include(users, userId)
      console.log worker, stats.hashrate

      CXUser.findOne {_id: userId}, (e, r) =>
        hrate = stats.hashrate / 1000
        user = new CXUser(r)
        @saveHrate(userId, user.nickname(), wrkName, hrate)
        cbx(null)

    async.each _.pairs(stats), updHrate, =>
      async.each users, ((d, c) => @updateTotalHrate(d,c) ), -> true

  getPoolFee: (cb = null) ->
    CXCurrency.findOne {_id: @currId}, (e, curr) =>
      return cb(e) if e
      @poolFee = curr.miningFee || 0
      cb(null, @poolFee) if cb

  getBlockStats: (txid, cb) ->
    retStats = (data) =>
      details = data?.details?[0]
      return cb('No details on tx') unless details
      stats =
        cat:    details.category
        conf:   data.confirmations
        reward: details.amount * Math.pow(10, 8)

      cb(null, stats)

    @rpc.call('gettransaction', [txid]).then(
      ((r) => retStats(r))
      ((e) => console.log e, cb(e))
    )

  getBlockFinder: (userId, cb) ->
    CXUser.findOne {_id: userId}, (e, r) =>
      return cb(e) if e
      user = new CXUser(r)
      cb(null, user.nickname())

  saveBlock: (block) ->
    async.series [
      ((cb) => @getPoolFee(cb))
      ((cb) => @getBlockStats(block.txid, cb))
      ((cb) => @getBlockFinder(block.finder, cb))
    ], (e, ret) =>
      [fee, stats, finder] = ret

      blockRec = new CXBlock
        _id:        Random.id()
        acc:        true
        cat:        stats.cat
        paid:       false
        time:       new Date()
        txid:       block.txid
        hash:       block.hash
        conf:       stats.conf
        dbTime:     new Date()
        finder:     finder
        currId:     @currId
        number:     block.height
        reward:     stats.reward
        timeSpent:  block.timeSpent

      blockRec.save (e, ret) =>
        return console.log(e, e.stack) if e
        console.log ret

        return if blockRec.cat == 'orphan'

        poolFee = Math.round(blockRec.reward / 100 * fee)
        fullReward = blockRec.reward - poolFee

        for user, figure of block.rewards
          r = Math.floor(figure * fullReward)
          console.log "User %s reward: %s", user, r
          bs = new CXBlockStat
            _id:    Random.id()
            time:   new Date()
            paid:   false
            blkId:  blockRec._id
            currId: @currId
            userId: user
            reward: r
          bs.save()

module.exports = CoinExShareLogger
