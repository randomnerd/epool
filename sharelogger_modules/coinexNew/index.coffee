ShareLogger = require('../../sharelogger')
async = require 'async'
_ = require 'underscore'
Pusher = require('pusher')
Mysql  = require('mysql')
class CoinExNewShareLogger extends ShareLogger
  constructor: (params, rpc) ->
    @connected = false
    @rpc = rpc
    @params = params
    @db = null
    @connected = false
    @currId = params.currencyId
    @flushInterval = params.flushInterval || 60
    @poolFee = 0
    @stats = {}
    @lastFlush = null
    @pusher = new Pusher
      appId:  params.pusherAppId
      key:    params.pusherKey
      secret: params.pusherSecret
    @dbSettings =
      host: params.dbHost
      port: params.dbPort
      user: params.dbUser
      password: params.dbPass
      database: params.dbName

    @db = Mysql.createConnection @dbSettings
    @db.connect (err) =>
      if err
        console.log(err)
      else
        @connected = true
        console.log 'CoinEX-new sharelogger connected'

  logShare: (share) -> true
  logBlock: (block) -> @saveBlock(block)
  logStats: (name, stats) ->
    @stats[name] = stats
    @flush()

  flush: (force = false) ->
    @lastFlush ||= new Date()
    return unless force || (new Date() - @lastFlush) / 1000 >= @flushInterval
    return unless @connected

    try
      @saveStats()
      @lastFlush = new Date()
    catch e
      console.log e, e.stack

  getWorkerId: (name, cb) ->
    q = "select id from workers where name = ?"
    @db.query q, [name], (err, rows) =>
      console.log 'getWorkerId error', err if err
      cb(rows[0]?.id)

  getUserId: (wrkId, cb) ->
    q = "select user_id from workers where id = ?"
    @db.query q, [wrkId], (err, rows) =>
      console.log 'getUserId error', err if err
      cb(rows[0]?.user_id)

  getUserIdByWrkName: (wrkName, cb) ->
    @getWorkerId wrkName, (id) => @getUserId id, cb

  getWorkerStatId: (wrkId, cb) ->
    return cb(null) unless wrkId
    q = "select id from worker_stats where currency_id = ? and worker_id = ?"
    @db.query q, [@currId, wrkId], (err, rows) =>
      console.log 'getWorkerStatId error', err if err
      return cb(null) if err
      return cb(id, wrkId) if id = rows[0]?.id
      q = "insert into worker_stats (worker_id, currency_id, created_at, updated_at) values (?, ?, utc_timestamp(), utc_timestamp())"
      @db.query q, [wrkId, @currId], (err, rows) =>
        console.log 'getWorkerStatId2 error', err if err
        @getWorkerStatId(wrkId, cb)

  getWorkerStatIdByName: (name, cb) ->
    @getWorkerId name, (id) => @getWorkerStatId id, cb

  updStat: (data, cb) ->
    [worker, stats] = data
    @getWorkerStatIdByName worker, (id, wrkId) =>
      q = "update worker_stats set hashrate = ?, accepted = ?, rejected = ?, blocks = ?, diff = ?, updated_at = utc_timestamp() where id = ?"
      @db.query q, [
        stats.hashrate,
        stats.accepted,
        stats.rejected,
        stats.blocks,
        stats.diff,
        id
      ], (err, rows) =>
        console.log 'updStat error', err if err
        cb(null, id)
        @getUserId wrkId, (userId) =>
          @pusher.trigger "private-worker-stats-#{userId}", "u",
            id:       id
            diff:     stats.diff
            blocks:   stats.blocks
            accepted: stats.accepted
            rejected: stats.rejected
            hashrate: stats.hashrate
            worker_id:   wrkId
            currency_id: @currId
            updated_at: new Date().toISOString()

  resetHrates: ->
    q = "update worker_stats set hashrate = 0 where currency_id = ?"
    @db.query q, [@currId], (err, rows) ->
      console.log 'resetHrates error', err if err
      true

  updatePoolHrate: ->
    q = "select sum(hashrate) as hashrate from worker_stats where currency_id = ? and updated_at > date_sub(utc_timestamp(), interval 5 minute)"
    @db.query q, [@currId], (err, rows) =>
      console.log 'updatePoolHrate error', err if err
      return unless hashrate = rows[0]?.hashrate
      q = "update currencies set hashrate = ?, updated_at = utc_timestamp() where id = ?"
      @db.query q, [hashrate, @currId]
      @pusher.trigger 'currencies', 'uu', {id: @currId, fields: {hashrate: hashrate}}

  saveStats: ->
    @resetHrates()
    async.map _.pairs(@stats), ((d,c)=> @updStat(d, c)), (err, statIds) =>
      @updatePoolHrate()

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

  getBlockFinder: (worker, cb) ->
    q = "select users.nickname as name, users.id as id from workers inner join users on users.id = workers.user_id where workers.name = ?"
    @db.query q, [worker], (err, rows) ->
      return cb(err) if err
      cb(null, {name: rows[0].name, id: rows[0].id})

  getPoolFee: (cb) ->
    q = "select mining_fee from currencies where id = ?"
    @db.query q, [@currId], (err, rows) ->
      return cb(err) if err
      cb(null, rows[0].mining_fee)

  updateLastBlockAt: ->
    q = "update currencies set last_block_at = utc_timestamp(), updated_at = utc_timestamp() where id = ?"
    @db.query q, [@currId]
    @pusher.trigger 'currencies', 'uu',
      id: @currId
      fields:
        last_block_at: new Date().toISOString()

  pushBlock: (block) ->
    q = "select id from blocks where txid = ?"
    @db.query q, [block.txid], (err, rows) =>
      return console.log(err) if err
      block.id = rows[0].id
      @pusher.trigger "blocks-#{@currId}", 'c', block
      @createBlockPayouts(block)

  saveBlock: (block) ->
    async.series [
      ((cb) => @getPoolFee(cb))
      ((cb) => @getBlockStats(block.txid, cb))
      ((cb) => @getBlockFinder(block.finder, cb))
    ], (e, ret) =>
      [fee, stats, finder] = ret
      return unless stats.reward

      b =
        category:       stats.cat
        paid:           0
        diff:           block.diff
        txid:           block.txid
        stats:          block.rewards
        finder:         finder.name
        number:         block.height
        reward:         stats.reward
        user_id:        finder.id
        time_spent:     block.timeSpent
        created_at:     new Date().toISOString()
        updated_at:     new Date().toISOString()
        currency_id:    @currId
        confirmations:  stats.conf
      console.log block

      q = "insert into blocks (category, paid, diff, txid, finder, number,
                               reward, user_id, time_spent, currency_id,
                               confirmations, created_at, updated_at) values
                               (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, utc_timestamp(), utc_timestamp())"
      @db.query q, [
        b.category, b.paid, b.diff, b.txid,
        b.finder, b.number, b.reward, b.user_id,
        b.time_spent, b.currency_id, b.confirmations
      ], (err, rows) =>
        return console.log(err, rows) if err
        @updateLastBlockAt()
        @pushBlock(b)
        return if block.category == 'orphan'

  createBlockPayouts: (block) ->
    amounts = {}
    setAmount = (data, cb) =>
      [user, figure] = data
      @getUserIdByWrkName user, (user_id) =>
        amounts[user_id] ||= 0
        amounts[user_id] += figure
        cb(null, true)

    async.map _.pairs(block.stats), setAmount, =>
      for user_id, amount of amounts
        bp =
          amount: amount
          user_id: user_id
          block_id: block.id
          created_at: new Date().toISOString()
          updated_at: new Date().toISOString()

        q = 'insert into block_payouts (user_id, block_id, amount, created_at, updated_at)
             values (?, ?, ?, utc_timestamp(), utc_timestamp())'
        @db.query q, [bp.user_id, bp.block_id, bp.amount], (err, rows) =>
          return console.log(err) if err
          @pushBlockPayout(bp)

  pushBlockPayout: (bp) ->
    q = 'select id from block_payouts where user_id = ? and block_id = ?'
    @db.query q, [bp.user_id, bp.block_id], (err, rows) =>
      return console.log(err) if err
      bp.id = rows[0].id
      @pusher.trigger "blockpayouts-#{@currId}", 'c', bp


module.exports = CoinExNewShareLogger
