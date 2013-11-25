
# run garbage collector every 3 minutes if available
(->
  require "coffee-script"
  Pool = undefined
  config = undefined
  config_path = undefined
  pool = undefined
  config_path = process.argv[2] or "./config"
  config = require(config_path)
  Pool = require("./pool")
  pool = new Pool(config)
  pool.start()
  setInterval gc, 180 * 1000  if typeof (gc) is "function"
).call this
