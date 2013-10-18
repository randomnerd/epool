class ShareLogger
  constructor: (params) ->
    @params = params

  log: (share) ->
    console.log share

module.exports = ShareLogger
