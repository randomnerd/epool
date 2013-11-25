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
        console.log 'CoinEX sharelogger connected'

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
    @db.query q, [worker], (err, rows) => cb(rows[0]?[0]?.id)

  getWorkerStatId: (wrkId, cb) ->
    q = "select id from worker_stats where currency_id = ? and worker_id = ?"
    @db.query q, [worker, @currId], (err, rows) =>
      return cb(null) if err
      return cb(id, wrkId) if id = rows[0]?[0]?.id
      q = "insert into worker_stats (worker_id, currency_id) values (?, ?)"
      @db.query q, [worker, @currId], (err, rows) =>
        return cb(null) if err
        @getWorkerStatId(wrkId, cb)

  getWorkerStatIdByName: (name, cb) ->
    @getWorkerId name, (id) => @getWorkerStatId id, cb

  updStat: (data, cb) ->
    [worker, stats] = data
    @getWorkerStatIdByName worker, (id, wrkId) =>
      q = "update worker_stats set hashrate = ?, accepted = ?, rejected = ?, blocks = ?, diff = ? where id = ?"
      @db.query q, [
        stats.hashrate,
        stats.accepted,
        stats.rejected,
        stats.blocks,
        stats.diff,
        id
      ], (err, rows) => cb(null, id)

  resetHrates: ->
    q = "update worker_stats set hashrate = 0 where currency_id = ?"
    @db.query q, [@currId], -> true

  updatePoolHrate: ->
    q = "select sum(hashrate) as hashrate from worker_stats where currency_id = ?"
    @db.query q, [@currId], (err, rows) =>
      return unless hashrate = rows[0]?[0]?.hashrate
      q = "update currencies set hashrate = ? where currency_id = ?"
      @db.query q, [hashrate, @currId]

  saveStats: ->
    @resetHrates()
    async.map _.pairs(@stats), ((d,c)=> @updStat(d, c)), (err, statIds) =>
      @updatePoolHrate()

  getPoolHashrate: (table, interval, share_diff, cb) ->
    f = (err, rows) ->
      if err then cb(false) else cb(rows[0]?[0]?.hashrate)

    q = "call pool_hashrate(?, ?, ?)"
    @db.query q, [table, interval, share_diff], f

module.exports = CoinExNewShareLogger
