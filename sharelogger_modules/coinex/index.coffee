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
    @flushInterval = 60
    @poolFee = 0
    @buffer =
      lastFlush: null
      stats:  []
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
    console.log name, stats
    @buffer.stats.push [name, stats]
    @flush()

  flush: (force = false) ->
    force = true unless @lastFlush
    return unless force || (new Date() - @lastFlush) / 1000 >= @flushInterval
    return unless @connected

    try
      @saveStats(@buffer.stats)
      @saveBlock(block) for block in @buffer.blocks
      @buffer.stats = []
      @buffer.blocks = []
      # @lastFlush = new Date()
    catch e
      console.log e, e.stack

  saveHrate: (userId, name, wrkName, hashrate) ->
    sel =
      currId: @currId
      userId: userId
      wrkName: wrkName

    CXHashrate.findOne sel, (e, rec) =>
      if !e && rec
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

      CXUser.findOne {_id: userId}, (e, r) =>
        hrate = stats.hashrate / 1000
        user = new CXUser(r)
        @saveHrate(userId, user.nickname(), wrkName, hrate)
        cbx(null)

    async.each stats, updHrate, =>
      async.each users, ((d, c) => @updateTotalHrate(d,c) ), -> true

  getPoolFee: (cb = null) ->
    console.log 'getPoolFee'
    CXCurrency.findOne {_id: @currId}, (e, curr) =>
      return cb(e) if e
      @poolFee = curr.miningFee || 0
      console.log 'getPoolFee =>', @poolFee
      cb(null, @poolFee) if cb

  getBlockStats: (txid, cb) ->
    console.log 'getBlockStats', txid
    retStats = (data) =>
      details = data?.details?[0]
      return cb('No details on tx') unless details
      stats =
        cat:    details.category
        conf:   data.confirmations
        reward: details.amount * Math.pow(10, 8)

      console.log 'getBlockStats =>', stats
      cb(null, stats)

    @rpc.call('gettransaction', [txid]).then(
      ((r) => retReward(r))
      ((e) => console.log e, cb(e))
    )

  getBlockFinder: (userId, cb) ->
    console.log 'getBlockFinder', userId
    CXUser.findOne {_id: userId}, (e, r) =>
      return cb(e) if e
      user = new CXUser(r)
      console.log 'getBlockFinder =>', user.nickname()
      cb(null, user.nickname())

  saveBlock: (block) ->
    async.series [
      ((cb) => @getPoolFee(cb))
      ((cb) => @getBlockStats(block.txid, cb))
      ((cb) => @getBlockFinder(block.finder, cb))
    ], (e, ret) =>
      console.log e, ret
      [fee, stats, finder] = ret

      block = new CXBlock
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

      console.log block
      block.save()

      return if block.cat == 'orphan'

      poolFee = Math.round(block.reward / 100 * fee)
      fullReward = block.reward - poolFee

      for user, figure of block.rewards
        bs = CXBlockStat.new
          time:   new Date()
          paid:   false
          blkId:  block._id
          currId: @currId
          userId: user
          reward: Math.floor(figure * fullReward)
        bs.save()

module.exports = CoinExShareLogger
